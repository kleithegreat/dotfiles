use std::{
    fmt, fs, io,
    path::{Path, PathBuf},
    process::{self, Command, Output},
    sync::atomic::{AtomicBool, Ordering},
    thread,
    time::Duration,
};

use crate::paths;
use serde::Serialize;

pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

const GAMMA: f64 = 2.2;
const STEP: f64 = 0.05;
const DIM_STEPS: u32 = 20;
const DIM_DELAY: Duration = Duration::from_millis(50);
const BACKLIGHT_ROOT: &str = "/sys/class/backlight";
const DIM_PID_PATH: &str = "/tmp/dim-screen.pid";
const DDC_DIM_STATE_FILE: &str = "dim-screen-ddc-state";
const DDC_BRIGHTNESS_VCP: &str = "10";

const SIGHUP: i32 = 1;
const SIGINT: i32 = 2;
const SIGQUIT: i32 = 3;
const SIGTERM: i32 = 15;
const SIG_ERR: usize = usize::MAX;

static DIM_ABORTED: AtomicBool = AtomicBool::new(false);

#[derive(Clone, Debug)]
enum BrightnessDevice {
    Backlight(String),
    Ddc {
        display: Option<String>,
        connector: Option<String>,
        label: Option<String>,
    },
}

#[derive(Clone, Debug)]
struct BrightnessState {
    device: BrightnessDevice,
    current: u64,
    max: u64,
}

#[derive(Clone, Debug, Serialize)]
struct BrightnessDeviceStatus {
    available: bool,
    kind: &'static str,
    device: String,
    label: String,
    raw: u64,
    max: u64,
    fraction: f64,
    percent: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    connector: Option<String>,
}

#[derive(Serialize)]
struct BrightnessStatus {
    #[serde(flatten)]
    primary: BrightnessDeviceStatus,
    devices: Vec<BrightnessDeviceStatus>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct DdcDisplay {
    display: String,
    connector: Option<String>,
    label: Option<String>,
}

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

pub fn status(json: bool) -> Result<()> {
    if json {
        let devices = available_device_statuses()?;
        let status = status_payload_for_devices(devices);
        println!("{}", serde_json::to_string(&status)?);
    } else {
        let state = resolve_state(None)?;
        let status = status_payload(&state)?;
        println!("{}: {}%", status.label, status.percent);
    }

    Ok(())
}

pub fn set(device: Option<&str>, percent: u16) -> Result<()> {
    let state = resolve_state(device)?;
    let fraction = (percent as f64 / 100.0).clamp(0.0, 1.0);
    let raw = match &state.device {
        BrightnessDevice::Backlight(_) => perceived_to_raw(fraction, state.max).max(1),
        BrightnessDevice::Ddc { .. } => fraction_to_raw(fraction, state.max),
    };

    set_raw(&state.device, raw)?;
    notify_quickshell_osd(display_fraction_for_raw(&state.device, raw, state.max));
    Ok(())
}

pub fn dim(device: Option<&str>) -> Result<()> {
    let state = resolve_state(device)?;
    let _pid_file = DimPidFile::create(Path::new(DIM_PID_PATH))?;
    install_dim_signal_handlers()?;

    if let BrightnessDevice::Backlight(device) = &state.device {
        brightnessctl(device, &["-s"])?;
    } else {
        save_ddc_dim_state(&state)?;
    }

    let current = state.current;
    let max = state.max;
    ensure_nonzero_max(max)?;

    if current == 0 {
        return Ok(());
    }

    let target = ((current as f64) * 0.3).floor() as u64;

    for raw in dim_ramp_raw_values(&state.device, current, target, max) {
        if DIM_ABORTED.load(Ordering::Relaxed) {
            break;
        }

        set_raw(&state.device, raw)?;

        if DIM_ABORTED.load(Ordering::Relaxed) {
            break;
        }

        thread::sleep(DIM_DELAY);
    }

    Ok(())
}

/// Compute the per-step raw values for the dim ramp. Both interpolation
/// endpoints use the device's display curve (gamma for backlight, linear for
/// DDC) so the per-step raw conversion is its exact inverse and the ramp moves
/// monotonically from `current` toward `target`.
fn dim_ramp_raw_values(device: &BrightnessDevice, current: u64, target: u64, max: u64) -> Vec<u64> {
    let current_perceived = display_fraction_for_raw(device, current, max);
    let target_perceived = display_fraction_for_raw(device, target, max);

    (0..DIM_STEPS)
        .map(|index| {
            let progress = (index + 1) as f64 / DIM_STEPS as f64;
            let perceived = current_perceived + (target_perceived - current_perceived) * progress;
            match device {
                BrightnessDevice::Backlight(_) => perceived_to_raw(perceived, max),
                BrightnessDevice::Ddc { .. } => fraction_to_raw(perceived, max),
            }
        })
        .collect()
}

pub fn restore(device: Option<&str>) -> Result<()> {
    let resolved = resolve_device(device)?;
    match resolved {
        BrightnessDevice::Backlight(device) => {
            brightnessctl(&device, &["-r"])?;
        }
        BrightnessDevice::Ddc { display, .. } => {
            let raw = read_ddc_dim_state(&display)?;
            set_raw(
                &BrightnessDevice::Ddc {
                    display,
                    connector: None,
                    label: None,
                },
                raw,
            )?;
            if let Ok(path) = ddc_dim_state_path() {
                let _ = fs::remove_file(path);
            }
        }
    }
    Ok(())
}

fn step(device: Option<&str>, direction: f64) -> Result<()> {
    let state = resolve_state(device)?;
    let current = state.current;
    let max = state.max;
    ensure_nonzero_max(max)?;

    let perceived = match &state.device {
        BrightnessDevice::Backlight(_) => raw_to_perceived(current, max),
        BrightnessDevice::Ddc { .. } => current as f64 / max as f64,
    };
    let next = (perceived + (direction * STEP)).clamp(0.0, 1.0);
    let raw = match &state.device {
        BrightnessDevice::Backlight(_) => perceived_to_raw(next, max),
        BrightnessDevice::Ddc { .. } => fraction_to_raw(next, max),
    };

    set_raw(&state.device, raw)?;
    notify_quickshell_osd(display_fraction_for_raw(&state.device, raw, max));
    Ok(())
}

fn resolve_state(device: Option<&str>) -> Result<BrightnessState> {
    let device = resolve_device(device)?;
    read_state(device)
}

fn resolve_device(device: Option<&str>) -> Result<BrightnessDevice> {
    if let Some(device) = device {
        if let Some(display) = parse_ddc_device(device) {
            return Ok(BrightnessDevice::Ddc {
                display,
                connector: None,
                label: None,
            });
        }

        return Ok(BrightnessDevice::Backlight(device.to_owned()));
    }

    if let Some(device) = first_backlight_device()? {
        return Ok(BrightnessDevice::Backlight(device));
    }

    let ddc = BrightnessDevice::Ddc {
        display: None,
        connector: None,
        label: None,
    };
    if read_state(ddc.clone()).is_ok() {
        return Ok(ddc);
    }

    Err(io::Error::new(
        io::ErrorKind::NotFound,
        "no backlight or DDC/CI brightness device found",
    )
    .into())
}

fn first_backlight_device() -> Result<Option<String>> {
    Ok(backlight_devices()?.into_iter().next())
}

fn backlight_devices() -> Result<Vec<String>> {
    let entries = match fs::read_dir(BACKLIGHT_ROOT) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error.into()),
    };

    let mut devices = Vec::new();
    for entry in entries {
        let entry = entry?;
        let name = entry.file_name().into_string().map_err(|_| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "backlight device name is not valid UTF-8",
            )
        })?;
        devices.push(name);
    }
    devices.sort();

    Ok(devices)
}

fn parse_ddc_device(device: &str) -> Option<Option<String>> {
    if device == "ddc" {
        return Some(None);
    }

    device
        .strip_prefix("ddc:")
        .or_else(|| device.strip_prefix("ddc-"))
        .map(|display| Some(display.to_owned()))
}

fn read_state(device: BrightnessDevice) -> Result<BrightnessState> {
    match &device {
        BrightnessDevice::Backlight(name) => {
            let current = brightness_value(name, "g")?;
            let max = brightness_value(name, "m")?;
            ensure_nonzero_max(max)?;
            Ok(BrightnessState {
                device,
                current,
                max,
            })
        }
        BrightnessDevice::Ddc { display, .. } => {
            let (current, max) = ddc_brightness_value(display.as_deref())?;
            ensure_nonzero_max(max)?;
            Ok(BrightnessState {
                device,
                current,
                max,
            })
        }
    }
}

fn available_device_statuses() -> Result<Vec<BrightnessDeviceStatus>> {
    let mut statuses = Vec::new();

    for device in backlight_devices()? {
        if let Ok(state) = read_state(BrightnessDevice::Backlight(device)) {
            statuses.push(status_payload(&state)?);
        }
    }

    for state in available_ddc_states() {
        statuses.push(status_payload(&state)?);
    }

    Ok(statuses)
}

fn available_ddc_states() -> Vec<BrightnessState> {
    let mut states = Vec::new();

    if let Ok(devices) = detected_ddc_devices() {
        for device in devices {
            if let Ok(state) = read_state(device) {
                states.push(state);
            }
        }
    }

    if states.is_empty() {
        let fallback = BrightnessDevice::Ddc {
            display: None,
            connector: None,
            label: None,
        };
        if let Ok(state) = read_state(fallback) {
            states.push(state);
        }
    }

    states
}

fn status_payload_for_devices(devices: Vec<BrightnessDeviceStatus>) -> BrightnessStatus {
    let primary = devices
        .first()
        .cloned()
        .unwrap_or_else(|| BrightnessDeviceStatus {
            available: false,
            kind: "",
            device: String::new(),
            label: String::new(),
            raw: 0,
            max: 0,
            fraction: 0.0,
            percent: 0,
            connector: None,
        });

    BrightnessStatus { primary, devices }
}

fn status_payload(state: &BrightnessState) -> Result<BrightnessDeviceStatus> {
    ensure_nonzero_max(state.max)?;
    let (kind, device, label, fraction, connector) = match &state.device {
        BrightnessDevice::Backlight(name) => (
            "backlight",
            name.clone(),
            name.replace('_', " "),
            raw_to_perceived(state.current, state.max),
            None,
        ),
        BrightnessDevice::Ddc {
            display,
            connector,
            label,
        } => {
            let device = display
                .as_ref()
                .map(|display| format!("ddc:{display}"))
                .unwrap_or_else(|| "ddc".to_owned());
            (
                "ddc",
                device,
                ddc_label(label.as_deref(), connector.as_deref()),
                state.current as f64 / state.max as f64,
                connector.clone(),
            )
        }
    };

    let fraction = fraction.clamp(0.0, 1.0);
    Ok(BrightnessDeviceStatus {
        available: true,
        kind,
        device,
        label,
        raw: state.current,
        max: state.max,
        fraction,
        percent: (fraction * 100.0).round() as u64,
        connector,
    })
}

fn ddc_label(label: Option<&str>, connector: Option<&str>) -> String {
    let label = label.map(str::trim).filter(|label| !label.is_empty());
    match (label, connector) {
        (Some(label), Some(connector)) => format!("{label} ({connector})"),
        (Some(label), None) => label.to_owned(),
        (None, Some(connector)) => format!("DDC/CI {connector}"),
        (None, None) => "DDC/CI monitor".to_owned(),
    }
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

fn set_raw(device: &BrightnessDevice, raw: u64) -> Result<()> {
    match device {
        BrightnessDevice::Backlight(name) => {
            brightnessctl(name, &["s", &raw.to_string()])?;
        }
        BrightnessDevice::Ddc { display, .. } => {
            ddcutil(
                display.as_deref(),
                &["setvcp", DDC_BRIGHTNESS_VCP, &raw.to_string()],
            )?;
        }
    }

    Ok(())
}

fn ddc_brightness_value(display: Option<&str>) -> Result<(u64, u64)> {
    let output = ddcutil(display, &["getvcp", DDC_BRIGHTNESS_VCP])?;
    let stdout = String::from_utf8(output.stdout)?;
    parse_ddc_brightness(&stdout).ok_or_else(|| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!(
                "could not parse ddcutil brightness output: {}",
                stdout.trim()
            ),
        )
        .into()
    })
}

fn ddcutil(display: Option<&str>, args: &[&str]) -> Result<Output> {
    let mut command_args = Vec::with_capacity(args.len() + 2);
    if let Some(display) = display {
        command_args.extend(["--display", display]);
    }
    command_args.extend(args.iter().copied());

    let output = Command::new("ddcutil").args(&command_args).output()?;
    if output.status.success() {
        return Ok(output);
    }

    Err(command_error("ddcutil", &command_args, &output).into())
}

fn detected_ddc_devices() -> Result<Vec<BrightnessDevice>> {
    let output = Command::new("ddcutil")
        .args(["detect", "--brief"])
        .output()?;
    if !output.status.success() {
        return Err(command_error("ddcutil", &["detect", "--brief"], &output).into());
    }

    let stdout = String::from_utf8(output.stdout)?;
    Ok(parse_ddc_detect_brief(&stdout)
        .into_iter()
        .map(|display| BrightnessDevice::Ddc {
            display: Some(display.display),
            connector: display.connector,
            label: display.label,
        })
        .collect())
}

fn parse_ddc_detect_brief(output: &str) -> Vec<DdcDisplay> {
    let mut displays = Vec::new();
    let mut current: Option<DdcDisplay> = None;

    for raw_line in output.lines() {
        let line = raw_line.trim();
        if let Some(rest) = line.strip_prefix("Display ") {
            if let Some(display) = current.take() {
                displays.push(display);
            }

            let display = rest
                .split_whitespace()
                .next()
                .unwrap_or("")
                .trim_end_matches(':')
                .to_owned();
            if !display.is_empty() {
                current = Some(DdcDisplay {
                    display,
                    connector: None,
                    label: None,
                });
            }
            continue;
        }

        let Some(display) = current.as_mut() else {
            continue;
        };

        if let Some(connector) = field_value(line, "DRM connector:") {
            display.connector = normalize_drm_connector(connector);
        } else if let Some(label) = field_value(line, "Monitor:") {
            display.label = nonempty_string(label);
        } else if display.label.is_none()
            && let Some(label) = field_value(line, "Model:")
        {
            display.label = nonempty_string(label);
        }
    }

    if let Some(display) = current {
        displays.push(display);
    }

    displays
}

fn field_value<'a>(line: &'a str, field: &str) -> Option<&'a str> {
    line.strip_prefix(field).map(str::trim)
}

fn nonempty_string(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_owned())
    }
}

fn normalize_drm_connector(value: &str) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() || trimmed.eq_ignore_ascii_case("unknown") {
        return None;
    }

    let base = trimmed.rsplit('/').next().unwrap_or(trimmed);
    if let Some(without_card) = strip_card_prefix(base) {
        return Some(without_card.to_owned());
    }

    Some(base.to_owned())
}

fn strip_card_prefix(value: &str) -> Option<&str> {
    let rest = value.strip_prefix("card")?;
    let digit_count = rest.chars().take_while(|ch| ch.is_ascii_digit()).count();
    let rest = rest.get(digit_count..)?;
    rest.strip_prefix('-')
}

fn parse_ddc_brightness(output: &str) -> Option<(u64, u64)> {
    if let (Some(current), Some(max)) = (
        number_after(output, "current value ="),
        number_after(output, "max value ="),
    ) {
        return Some((current, max));
    }

    let numbers: Vec<u64> = output
        .split(|ch: char| !ch.is_ascii_digit())
        .filter(|part| !part.is_empty())
        .filter_map(|part| part.parse().ok())
        .collect();

    if numbers.len() >= 2 {
        Some((numbers[numbers.len() - 2], numbers[numbers.len() - 1]))
    } else {
        None
    }
}

fn number_after(text: &str, marker: &str) -> Option<u64> {
    let tail = text.split_once(marker)?.1.trim_start();
    let digits: String = tail.chars().take_while(|ch| ch.is_ascii_digit()).collect();
    digits.parse().ok()
}

fn save_ddc_dim_state(state: &BrightnessState) -> Result<()> {
    let BrightnessDevice::Ddc { display, .. } = &state.device else {
        return Ok(());
    };
    let display = display.as_deref().unwrap_or("");
    let path = ddc_dim_state_path()?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, format!("{display}\n{}\n", state.current))?;
    Ok(())
}

fn read_ddc_dim_state(display: &Option<String>) -> Result<u64> {
    let contents = fs::read_to_string(ddc_dim_state_path()?)?;
    let mut lines = contents.lines();
    let saved_display = lines.next().unwrap_or("");
    let raw = lines
        .next()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "missing saved DDC brightness"))?
        .parse()?;

    if saved_display != display.as_deref().unwrap_or("") {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "saved DDC display does not match",
        )
        .into());
    }

    Ok(raw)
}

fn ddc_dim_state_path() -> Result<PathBuf> {
    Ok(paths::xdg_runtime_dir()?
        .join("desktopctl")
        .join(DDC_DIM_STATE_FILE))
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

fn fraction_to_raw(fraction: f64, max: u64) -> u64 {
    let raw = (max as f64 * fraction.clamp(0.0, 1.0)).round();
    raw.clamp(0.0, max as f64) as u64
}

fn display_fraction_for_raw(device: &BrightnessDevice, raw: u64, max: u64) -> f64 {
    match device {
        BrightnessDevice::Backlight(_) => raw_to_perceived(raw, max),
        BrightnessDevice::Ddc { .. } => raw as f64 / max as f64,
    }
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

impl fmt::Display for BrightnessDevice {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            BrightnessDevice::Backlight(device) => write!(formatter, "{device}"),
            BrightnessDevice::Ddc {
                display: Some(display),
                ..
            } => write!(formatter, "ddc:{display}"),
            BrightnessDevice::Ddc { display: None, .. } => write!(formatter, "ddc"),
        }
    }
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

    #[test]
    fn parse_ddc_brightness_accepts_default_output() {
        let output = "VCP code 0x10 (Brightness): current value =    42, max value =   100";

        assert_eq!(parse_ddc_brightness(output), Some((42, 100)));
    }

    #[test]
    fn parse_ddc_device_accepts_display_override() {
        assert_eq!(parse_ddc_device("ddc"), Some(None));
        assert_eq!(parse_ddc_device("ddc:2"), Some(Some("2".to_owned())));
        assert_eq!(parse_ddc_device("intel_backlight"), None);
    }

    #[test]
    fn parse_ddc_detect_brief_extracts_display_metadata() {
        let output = r#"
Display 1
   I2C bus:             /dev/i2c-9
   DRM connector:       card1-HDMI-A-1
   Monitor:             BNQ ZOWIE XL LCD

Display 2
   I2C bus:             /dev/i2c-10
   DRM connector:       card1-DP-3
   EDID synopsis:
      Model:            UltraFine
"#;

        assert_eq!(
            parse_ddc_detect_brief(output),
            vec![
                DdcDisplay {
                    display: "1".to_owned(),
                    connector: Some("HDMI-A-1".to_owned()),
                    label: Some("BNQ ZOWIE XL LCD".to_owned()),
                },
                DdcDisplay {
                    display: "2".to_owned(),
                    connector: Some("DP-3".to_owned()),
                    label: Some("UltraFine".to_owned()),
                },
            ]
        );
    }

    #[test]
    fn normalize_drm_connector_strips_card_prefix() {
        assert_eq!(
            normalize_drm_connector("card0-eDP-1"),
            Some("eDP-1".to_owned())
        );
        assert_eq!(
            normalize_drm_connector("/sys/class/drm/card1-DP-2"),
            Some("DP-2".to_owned())
        );
        assert_eq!(normalize_drm_connector("unknown"), None);
    }

    #[test]
    fn display_fraction_for_backlight_reports_actual_nonzero_raw_value() {
        let device = BrightnessDevice::Backlight("intel_backlight".to_owned());

        assert!(display_fraction_for_raw(&device, 1, 100) > 0.0);
    }

    #[test]
    fn ddc_dim_ramp_descends_monotonically_to_the_raw_target() {
        let device = BrightnessDevice::Ddc {
            display: None,
            connector: None,
            label: None,
        };
        let current = 80;
        let target = 24; // floor(80 * 0.3)

        let ramp = dim_ramp_raw_values(&device, current, target, 100);

        assert_eq!(ramp.len(), DIM_STEPS as usize);
        assert!(ramp.first().is_some_and(|raw| *raw <= current));
        assert!(ramp.windows(2).all(|pair| pair[1] <= pair[0]));
        assert_eq!(ramp.last(), Some(&target));
    }

    #[test]
    fn backlight_dim_ramp_descends_monotonically_in_raw_space() {
        let device = BrightnessDevice::Backlight("intel_backlight".to_owned());
        let current = 80;
        let target = 24;

        let ramp = dim_ramp_raw_values(&device, current, target, 100);

        assert!(ramp.first().is_some_and(|raw| *raw <= current));
        assert!(ramp.windows(2).all(|pair| pair[1] <= pair[0]));
        assert!(ramp.last().is_some_and(|raw| *raw <= target));
    }
}
