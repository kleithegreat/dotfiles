use crate::{
    hypr,
    ipc::{self, RpcRequest},
    paths, proc_util, solar, theme,
};
use serde::{Deserialize, Serialize};
use std::{
    io::{self, BufReader, Read, Write},
    net::Shutdown,
    os::unix::net::UnixStream,
    path::PathBuf,
    thread,
    time::{Duration, Instant},
};

pub const NIGHT_LIGHT_MIN_TEMP: i32 = 3000;
pub const NIGHT_LIGHT_MAX_TEMP: i32 = 6500;
const PROCESS_SETTLE_TIMEOUT: Duration = Duration::from_secs(1);
const PROCESS_SETTLE_POLL: Duration = Duration::from_millis(25);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NightLightMode {
    Auto,
    On,
    Off,
}

impl NightLightMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Auto => "auto",
            Self::On => "on",
            Self::Off => "off",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NightLightStatus {
    pub mode: NightLightMode,
    pub running: bool,
    pub temperature: Option<i32>,
    pub target_temperature: i32,
    pub dark_hint: bool,
    pub scheduled_running: bool,
    pub scheduled_dark_hint: bool,
}

impl NightLightStatus {
    pub(crate) fn observe(
        mode: NightLightMode,
        target_temperature: i32,
        solar_status: &solar::SolarStatus,
    ) -> crate::Result<Self> {
        let process = hyprsunset_process_state();
        Ok(Self {
            mode,
            running: process.running,
            temperature: process.temperature,
            target_temperature,
            dark_hint: current_dark_hint()?,
            scheduled_running: solar_status.is_night,
            scheduled_dark_hint: solar_status.is_dark,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct HyprsunsetProcessState {
    pub running: bool,
    pub temperature: Option<i32>,
}

pub fn run(command: crate::NightLightCommand) -> crate::Result<()> {
    match command {
        crate::NightLightCommand::Status(args) => cmd_status(args.json),
        crate::NightLightCommand::On(args) => cmd_set_mode(NightLightMode::On, args.temp),
        crate::NightLightCommand::Off(args) => cmd_set_mode(NightLightMode::Off, args.temp),
        crate::NightLightCommand::Auto(args) => cmd_set_mode(NightLightMode::Auto, args.temp),
        crate::NightLightCommand::Toggle => cmd_toggle(),
    }
}

pub fn request_status() -> crate::Result<NightLightStatus> {
    match ipc::send::<NightLightStatus>(RpcRequest::NightLightStatus, ipc::DEFAULT_TIMEOUT) {
        Ok(status) => Ok(status),
        Err(error) if ipc::socket_unavailable(error.as_ref()) => fallback_status(),
        Err(error) => Err(error),
    }
}

pub fn request_mode(
    mode: NightLightMode,
    temperature: Option<i32>,
) -> crate::Result<NightLightStatus> {
    ipc::mutate(
        RpcRequest::NightLightSet { mode, temperature },
        ipc::DEFAULT_TIMEOUT,
        Duration::ZERO,
    )
}

pub fn request_toggle() -> crate::Result<NightLightStatus> {
    ipc::mutate(
        RpcRequest::NightLightToggle,
        ipc::DEFAULT_TIMEOUT,
        Duration::ZERO,
    )
}

pub(crate) fn normalize_temperature(value: i32) -> crate::Result<i32> {
    let rounded = ((i64::from(value) + 50) / 100) * 100;
    if !(i64::from(NIGHT_LIGHT_MIN_TEMP)..=i64::from(NIGHT_LIGHT_MAX_TEMP)).contains(&rounded) {
        return Err(crate::invalid_input(format!(
            "night-light temperature must be between {}K and {}K",
            NIGHT_LIGHT_MIN_TEMP, NIGHT_LIGHT_MAX_TEMP
        ))
        .into());
    }

    Ok(rounded as i32)
}

pub(crate) fn hyprsunset_process_state() -> HyprsunsetProcessState {
    let processes = proc_util::find_processes("hyprsunset");
    let Some(process) = processes.first() else {
        return HyprsunsetProcessState {
            running: false,
            temperature: None,
        };
    };

    let command_line = process.args.join(" ");
    HyprsunsetProcessState {
        running: true,
        temperature: hyprsunset_current_temperature()
            .or_else(|| parse_temperature_from_args(&command_line)),
    }
}

pub(crate) fn ensure_hyprsunset_running(target_temperature: i32) -> crate::Result<()> {
    let normalized = normalize_temperature(target_temperature)?;
    let state = hyprsunset_process_state();
    if state.running && state.temperature == Some(normalized) {
        return Ok(());
    }

    if state.running {
        if set_hyprsunset_temperature(normalized).is_ok() {
            return Ok(());
        }

        stop_hyprsunset()?;
    }

    let command = format!("hyprsunset -t {normalized}");
    hypr::dispatch(&hypr::exec_dispatcher(&command))?;
    wait_for_hyprsunset(true);
    Ok(())
}

/// Signals and spawns are asynchronous; the status published right after must
/// describe the process table as it settles, not as it was a moment ago.
fn wait_for_hyprsunset(running: bool) {
    let deadline = Instant::now() + PROCESS_SETTLE_TIMEOUT;
    while hyprsunset_process_state().running != running && Instant::now() < deadline {
        thread::sleep(PROCESS_SETTLE_POLL);
    }
}

pub(crate) fn stop_hyprsunset() -> crate::Result<()> {
    proc_util::signal_processes("hyprsunset", libc::SIGTERM)?;
    wait_for_hyprsunset(false);
    Ok(())
}

pub(crate) fn current_dark_hint() -> crate::Result<bool> {
    Ok(theme::resolve::load_state()?.dark_hint)
}

fn cmd_status(json_output: bool) -> crate::Result<()> {
    let status = request_status()?;
    if json_output {
        println!("{}", serde_json::to_string(&status)?);
        return Ok(());
    }

    println!("Mode:               {}", status.mode.as_str());
    println!("Hyprsunset running: {}", status.running);
    match status.temperature {
        Some(temperature) => println!("Temperature:        {temperature}K"),
        None => println!("Temperature:        off"),
    }
    println!("Target temperature: {}K", status.target_temperature);
    println!("Dark hint:          {}", status.dark_hint);
    println!("Scheduled running:  {}", status.scheduled_running);
    println!("Scheduled dark:     {}", status.scheduled_dark_hint);
    Ok(())
}

fn cmd_set_mode(mode: NightLightMode, temperature: Option<i32>) -> crate::Result<()> {
    let status = request_mode(mode, temperature)?;
    print_set_mode_summary(status);
    Ok(())
}

fn cmd_toggle() -> crate::Result<()> {
    let status = request_toggle()?;
    print_set_mode_summary(status);
    Ok(())
}

fn print_set_mode_summary(status: NightLightStatus) {
    let temperature = status
        .temperature
        .map(|value| format!("{value}K"))
        .unwrap_or_else(|| "off".to_owned());
    println!(
        "Night-light mode: {} (running={}, temperature={temperature})",
        status.mode.as_str(),
        status.running
    );
}

fn fallback_status() -> crate::Result<NightLightStatus> {
    let location = solar::resolve_location()?;
    let solar_status = solar::status_for_now(chrono::Local::now(), location);
    NightLightStatus::observe(NightLightMode::Auto, solar::HYPRSUNSET_TEMP, &solar_status)
}

fn hyprsunset_current_temperature() -> Option<i32> {
    hyprsunset_ipc_request("temperature")
        .ok()
        .and_then(|reply| parse_temperature_reply(&reply).ok())
}

fn set_hyprsunset_temperature(temperature: i32) -> crate::Result<()> {
    let normalized = normalize_temperature(temperature)?;
    let reply = hyprsunset_ipc_request(&format!("temperature {normalized}"))?;
    if reply.trim() == "ok" {
        return Ok(());
    }

    Err(io::Error::other(format!(
        "hyprsunset IPC rejected temperature update: {reply}"
    ))
    .into())
}

fn hyprsunset_ipc_request(request: &str) -> crate::Result<String> {
    let socket_path = hyprsunset_socket_path()?;
    let mut stream = UnixStream::connect(&socket_path).map_err(|error| {
        io::Error::new(
            error.kind(),
            format!("failed to connect to {}: {error}", socket_path.display()),
        )
    })?;
    stream.set_read_timeout(Some(ipc::DEFAULT_TIMEOUT))?;
    stream.set_write_timeout(Some(ipc::DEFAULT_TIMEOUT))?;

    stream.write_all(request.as_bytes())?;
    stream.shutdown(Shutdown::Write)?;

    let mut response = String::new();
    BufReader::new(stream).read_to_string(&mut response)?;
    Ok(response.trim().to_owned())
}

/// Started without a signature, hyprsunset binds directly under `hypr/`.
fn hyprsunset_socket_path() -> crate::Result<PathBuf> {
    hypr::instance_socket(".hyprsunset.sock").or_else(|error| {
        let unscoped = paths::xdg_runtime_dir()?.join("hypr/.hyprsunset.sock");
        if unscoped.exists() {
            Ok(unscoped)
        } else {
            Err(error)
        }
    })
}

fn parse_temperature_reply(reply: &str) -> crate::Result<i32> {
    reply.trim().parse::<i32>().map_err(|error| {
        crate::invalid_data(format!(
            "invalid hyprsunset IPC temperature reply '{reply}': {error}"
        ))
        .into()
    })
}

fn parse_temperature_from_args(args: &str) -> Option<i32> {
    let tokens = args.split_whitespace().collect::<Vec<_>>();
    for (index, token) in tokens.iter().enumerate() {
        if *token == "-t" || *token == "--temperature" {
            return tokens.get(index + 1).and_then(|value| value.parse().ok());
        }

        if let Some(value) = token.strip_prefix("--temperature=") {
            return value.parse().ok();
        }
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_temperature_rounds_and_validates_bounds() {
        for (input, expected) in [
            (4549, Some(4500)),
            (4550, Some(4600)),
            (2900, None),
            (6600, None),
            (i32::MAX, None),
        ] {
            assert_eq!(
                normalize_temperature(input).ok(),
                expected,
                "temperature={input}"
            );
        }
    }

    #[test]
    fn parse_temperature_from_args_supports_short_and_long_flags() {
        for (args, expected) in [
            ("hyprsunset -t 4300", Some(4300)),
            ("hyprsunset --temperature=5100", Some(5100)),
            ("hyprsunset", None),
        ] {
            assert_eq!(parse_temperature_from_args(args), expected, "{args}");
        }
    }
}
