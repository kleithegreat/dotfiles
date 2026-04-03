use crate::{hypr, paths, solar, theme};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{
    io::{self, BufRead, BufReader, Write},
    os::unix::net::UnixStream,
    process::Command,
};

pub const METHOD_NIGHT_LIGHT_STATUS: &str = "night_light.status";
pub const METHOD_NIGHT_LIGHT_SET: &str = "night_light.set";
pub const METHOD_NIGHT_LIGHT_TOGGLE: &str = "night_light.toggle";
pub const NIGHT_LIGHT_MIN_TEMP: i32 = 3000;
pub const NIGHT_LIGHT_MAX_TEMP: i32 = 6500;

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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NightLightSetParams {
    pub mode: NightLightMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub temperature: Option<i32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct HyprsunsetProcessState {
    pub running: bool,
    pub temperature: Option<i32>,
}

#[derive(Debug, Serialize)]
struct RequestEnvelope<P> {
    method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    params: Option<P>,
}

#[derive(Debug, Deserialize)]
struct ResponseEnvelope<T> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

pub fn run(args: crate::NightLightArgs) -> crate::Result<()> {
    match args.command {
        crate::NightLightCommand::Status(args) => cmd_status(args.json),
        crate::NightLightCommand::On(args) => cmd_set_mode(NightLightMode::On, args.temp),
        crate::NightLightCommand::Off => cmd_set_mode(NightLightMode::Off, None),
        crate::NightLightCommand::Auto => cmd_set_mode(NightLightMode::Auto, None),
        crate::NightLightCommand::Toggle => cmd_toggle(),
    }
}

pub fn request_status() -> crate::Result<NightLightStatus> {
    match send_request::<(), NightLightStatus>(METHOD_NIGHT_LIGHT_STATUS, None) {
        Ok(status) => Ok(status),
        Err(error) if socket_unavailable(error.as_ref()) => fallback_status(),
        Err(error) => Err(error),
    }
}

pub fn request_mode(
    mode: NightLightMode,
    temperature: Option<i32>,
) -> crate::Result<NightLightStatus> {
    let params = NightLightSetParams { mode, temperature };
    send_request(METHOD_NIGHT_LIGHT_SET, Some(params))
}

pub fn request_toggle() -> crate::Result<NightLightStatus> {
    send_request::<(), NightLightStatus>(METHOD_NIGHT_LIGHT_TOGGLE, None)
}

pub(crate) fn normalize_temperature(value: i32) -> crate::Result<i32> {
    let rounded = ((value + 50) / 100) * 100;
    if !(NIGHT_LIGHT_MIN_TEMP..=NIGHT_LIGHT_MAX_TEMP).contains(&rounded) {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!(
                "night-light temperature must be between {}K and {}K",
                NIGHT_LIGHT_MIN_TEMP, NIGHT_LIGHT_MAX_TEMP
            ),
        )
        .into());
    }

    Ok(rounded)
}

pub(crate) fn hyprsunset_process_state() -> HyprsunsetProcessState {
    let output = match Command::new("ps")
        .args(["-C", "hyprsunset", "-o", "args="])
        .output()
    {
        Ok(output) if output.status.success() => output,
        _ => {
            return HyprsunsetProcessState {
                running: false,
                temperature: None,
            };
        }
    };

    let args = String::from_utf8_lossy(&output.stdout);
    let Some(command_line) = args.lines().find(|line| !line.trim().is_empty()) else {
        return HyprsunsetProcessState {
            running: false,
            temperature: None,
        };
    };

    HyprsunsetProcessState {
        running: true,
        temperature: parse_temperature_from_args(command_line),
    }
}

pub(crate) fn ensure_hyprsunset_running(target_temperature: i32) -> crate::Result<()> {
    let normalized = normalize_temperature(target_temperature)?;
    let state = hyprsunset_process_state();
    if state.running && state.temperature == Some(normalized) {
        return Ok(());
    }

    if state.running {
        stop_hyprsunset()?;
    }

    let command = format!("hyprsunset -t {normalized}");
    hypr::dispatch(&["exec", &command])
}

pub(crate) fn stop_hyprsunset() -> crate::Result<()> {
    let _ = Command::new("pkill").args(["-x", "hyprsunset"]).output();
    Ok(())
}

pub(crate) fn current_dark_hint() -> crate::Result<bool> {
    Ok(theme::resolve::load_state()?.dark_hint)
}

pub(crate) fn apply_dark_hint_if_needed(enabled: bool) -> crate::Result<()> {
    if current_dark_hint()? == enabled {
        return Ok(());
    }

    theme::set_dark_hint(enabled)
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
    let process = hyprsunset_process_state();
    Ok(NightLightStatus {
        mode: NightLightMode::Auto,
        running: process.running,
        temperature: process.temperature,
        target_temperature: solar::HYPRSUNSET_TEMP,
        dark_hint: current_dark_hint()?,
        scheduled_running: solar_status.is_night,
        scheduled_dark_hint: solar_status.is_dark,
    })
}

fn send_request<P, T>(method: &str, params: Option<P>) -> crate::Result<T>
where
    P: Serialize,
    T: DeserializeOwned,
{
    let socket_path = paths::xdg_runtime_dir()?.join("desktopctl.sock");
    let mut stream = UnixStream::connect(&socket_path).map_err(|error| {
        io::Error::new(
            error.kind(),
            format!("failed to connect to {}: {error}", socket_path.display()),
        )
    })?;

    let payload = RequestEnvelope {
        method: method.to_owned(),
        params,
    };
    let request = serde_json::to_string(&payload)?;
    stream.write_all(request.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;

    let mut reader = BufReader::new(stream);
    let mut response_line = String::new();
    if reader.read_line(&mut response_line)? == 0 {
        return Err(io::Error::new(
            io::ErrorKind::UnexpectedEof,
            "desktopctl daemon closed the socket without responding",
        )
        .into());
    }

    let response: ResponseEnvelope<T> =
        serde_json::from_str(response_line.trim_end()).map_err(|error| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("invalid response from desktopctl daemon: {error}"),
            )
        })?;

    if response.ok {
        return response.data.ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                "desktopctl daemon returned success without data",
            )
            .into()
        });
    }

    Err(io::Error::other(
        response
            .error
            .unwrap_or_else(|| "desktopctl daemon request failed".to_owned()),
    )
    .into())
}

fn socket_unavailable(error: &(dyn std::error::Error + 'static)) -> bool {
    error.downcast_ref::<io::Error>().is_some_and(|io_error| {
        matches!(
            io_error.kind(),
            io::ErrorKind::NotFound
                | io::ErrorKind::ConnectionRefused
                | io::ErrorKind::ConnectionReset
                | io::ErrorKind::PermissionDenied
        )
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
    fn normalize_temperature_rounds_to_nearest_hundred() {
        assert_eq!(
            normalize_temperature(4549).expect("valid temperature"),
            4500
        );
        assert_eq!(
            normalize_temperature(4550).expect("valid temperature"),
            4600
        );
    }

    #[test]
    fn normalize_temperature_rejects_values_out_of_range() {
        assert!(normalize_temperature(2900).is_err());
        assert!(normalize_temperature(6600).is_err());
    }

    #[test]
    fn parse_temperature_from_args_supports_short_and_long_flags() {
        assert_eq!(
            parse_temperature_from_args("hyprsunset -t 4300"),
            Some(4300)
        );
        assert_eq!(
            parse_temperature_from_args("hyprsunset --temperature=5100"),
            Some(5100)
        );
        assert_eq!(parse_temperature_from_args("hyprsunset"), None);
    }
}
