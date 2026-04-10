use std::{
    fs, io,
    path::{Path, PathBuf},
    process::{self, Command, Output},
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::Duration,
};

use crate::paths;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

const GAMMA: f64 = 2.2;
const STEP: f64 = 0.05;
const DIM_STEPS: u32 = 20;
const DIM_DELAY: Duration = Duration::from_millis(50);
const BACKLIGHT_ROOT: &str = "/sys/class/backlight";
const DIM_PID_PATH: &str = "/tmp/dim-screen.pid";

const SIGHUP: i32 = 1;
const SIGINT: i32 = 2;
const SIGQUIT: i32 = 3;
const SIGTERM: i32 = 15;
const SIG_ERR: usize = usize::MAX;

static DIM_ABORTED: AtomicBool = AtomicBool::new(false);

unsafe extern "C" {
    fn signal(sig: i32, handler: usize) -> usize;
}

extern "C" fn handle_dim_signal(_signal: i32) {
    DIM_ABORTED.store(true, Ordering::Relaxed);
}

pub fn up(device: Option<&str>) -> Result<()> {
    step(device, 1.0)
}

pub fn down(device: Option<&str>) -> Result<()> {
    step(device, -1.0)
}

pub fn dim(device: Option<&str>) -> Result<()> {
    let device = resolve_device(device)?;
    let _pid_file = DimPidFile::create(Path::new(DIM_PID_PATH))?;
    install_dim_signal_handlers()?;

    brightnessctl(&device, &["-s"])?;

    let current = brightness_value(&device, "g")?;
    let max = brightness_value(&device, "m")?;
    ensure_nonzero_max(max)?;

    if current == 0 {
        return Ok(());
    }

    let current_perceived = raw_to_perceived(current, max);
    let target = ((current as f64) * 0.3).floor() as u64;
    let target_perceived = raw_to_perceived(target, max);

    for index in 0..DIM_STEPS {
        if DIM_ABORTED.load(Ordering::Relaxed) {
            break;
        }

        let progress = (index + 1) as f64 / DIM_STEPS as f64;
        let perceived = current_perceived + (target_perceived - current_perceived) * progress;
        let raw = perceived_to_raw(perceived, max);

        brightnessctl(&device, &["s", &raw.to_string()])?;

        if DIM_ABORTED.load(Ordering::Relaxed) {
            break;
        }

        thread::sleep(DIM_DELAY);
    }

    Ok(())
}

pub fn restore(device: Option<&str>) -> Result<()> {
    let device = resolve_device(device)?;
    brightnessctl(&device, &["-r"])?;
    Ok(())
}

fn step(device: Option<&str>, direction: f64) -> Result<()> {
    let device = resolve_device(device)?;
    let current = brightness_value(&device, "g")?;
    let max = brightness_value(&device, "m")?;
    ensure_nonzero_max(max)?;

    let perceived = raw_to_perceived(current, max);
    let next = (perceived + (direction * STEP)).clamp(0.0, 1.0);
    let raw = perceived_to_raw(next, max);

    brightnessctl(&device, &["s", &raw.to_string()])?;
    notify_quickshell_osd(next);
    Ok(())
}

fn resolve_device(device: Option<&str>) -> Result<String> {
    if let Some(device) = device {
        return Ok(device.to_owned());
    }

    let entry = fs::read_dir(BACKLIGHT_ROOT)?
        .find_map(|entry| entry.ok())
        .ok_or_else(|| io::Error::new(io::ErrorKind::NotFound, "no backlight devices found"))?;

    let name = entry.file_name();
    let device = name.into_string().map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            "backlight device name is not valid UTF-8",
        )
    })?;

    Ok(device)
}

fn brightness_value(device: &str, arg: &str) -> Result<u64> {
    let output = brightnessctl(device, &[arg])?;
    let value = String::from_utf8(output.stdout)?;
    Ok(value.trim().parse()?)
}

fn brightnessctl(device: &str, args: &[&str]) -> Result<Output> {
    let mut command_args = Vec::with_capacity(args.len() + 2);
    command_args.extend(["-d", device]);
    command_args.extend(args.iter().copied());

    let output = Command::new("brightnessctl").args(&command_args).output()?;
    if output.status.success() {
        return Ok(output);
    }

    Err(command_error("brightnessctl", &command_args, &output).into())
}

fn notify_quickshell_osd(perceived_fraction: f64) {
    let percent = (perceived_fraction * 100.0).round() as i32;
    let qs_path = match paths::repo_root() {
        Ok(root) => root.join("config/quickshell"),
        Err(_) => return,
    };

    let _ = Command::new("qs")
        .args(["-p"])
        .arg(qs_path)
        .args(["ipc", "call", "brightness", "osd", &percent.to_string()])
        .output();
}

fn ensure_nonzero_max(max: u64) -> Result<()> {
    if max == 0 {
        return Err(io::Error::other("brightness maximum is zero").into());
    }

    Ok(())
}

fn raw_to_perceived(raw: u64, max: u64) -> f64 {
    (raw as f64 / max as f64).powf(1.0 / GAMMA)
}

fn perceived_to_raw(perceived: f64, max: u64) -> u64 {
    let raw = (max as f64 * perceived.clamp(0.0, 1.0).powf(GAMMA)).floor();
    raw.clamp(0.0, max as f64) as u64
}

fn install_dim_signal_handlers() -> io::Result<()> {
    DIM_ABORTED.store(false, Ordering::Relaxed);

    for signal_number in [SIGHUP, SIGINT, SIGQUIT, SIGTERM] {
        let previous = unsafe { signal(signal_number, handle_dim_signal as *const () as usize) };
        if previous == SIG_ERR {
            return Err(io::Error::last_os_error());
        }
    }

    Ok(())
}

fn command_error(binary: &str, args: &[&str], output: &Output) -> io::Error {
    let stderr = String::from_utf8_lossy(&output.stderr);
    let detail = if stderr.trim().is_empty() {
        "(no stderr)".to_owned()
    } else {
        stderr.trim().to_owned()
    };

    io::Error::other(format!("{binary} {} failed: {detail}", args.join(" ")))
}

struct DimPidFile {
    path: PathBuf,
}

impl DimPidFile {
    fn create(path: &Path) -> io::Result<Self> {
        fs::write(path, format!("{}\n", process::id()))?;
        Ok(Self {
            path: path.to_path_buf(),
        })
    }
}

impl Drop for DimPidFile {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn raw_to_perceived_uses_gamma_curve() {
        let perceived = raw_to_perceived(25, 100);

        assert!((perceived - 0.532_520_544_7).abs() < 1e-9);
    }

    #[test]
    fn perceived_to_raw_clamps_inputs_and_rounds_down() {
        assert_eq!(perceived_to_raw(-0.25, 200), 0);
        assert_eq!(perceived_to_raw(1.5, 200), 200);
        assert_eq!(perceived_to_raw(0.5, 100), 21);
    }

    #[test]
    fn perceptual_steps_move_in_the_expected_direction_and_clamp_at_bounds() {
        let current = 25;
        let max = 100;
        let perceived = raw_to_perceived(current, max);

        let stepped_up = perceived_to_raw((perceived + STEP).clamp(0.0, 1.0), max);
        let stepped_down = perceived_to_raw((perceived - STEP).clamp(0.0, 1.0), max);

        assert!(stepped_up > current);
        assert!(stepped_down < current);
        assert_eq!(
            perceived_to_raw((raw_to_perceived(max, max) + STEP).clamp(0.0, 1.0), max),
            max
        );
        assert_eq!(
            perceived_to_raw((raw_to_perceived(0, max) - STEP).clamp(0.0, 1.0), max),
            0
        );
    }

    #[test]
    fn ensure_nonzero_max_rejects_zero() {
        assert!(ensure_nonzero_max(0).is_err());
        assert!(ensure_nonzero_max(1).is_ok());
    }
}
