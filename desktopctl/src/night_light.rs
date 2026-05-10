use crate::{hypr, paths, solar, theme};
use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{
    env, fs,
    io::{self, BufRead, BufReader, Read, Write},
    net::Shutdown,
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    process::Command,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

pub const METHOD_NIGHT_LIGHT_STATUS: &str = "night_light.status";
pub const METHOD_NIGHT_LIGHT_SET: &str = "night_light.set";
pub const METHOD_NIGHT_LIGHT_TOGGLE: &str = "night_light.toggle";
pub const NIGHT_LIGHT_MIN_TEMP: i32 = 3000;
pub const NIGHT_LIGHT_MAX_TEMP: i32 = 6500;
const SOCKET_TIMEOUT: Duration = Duration::from_secs(3);

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
        crate::NightLightCommand::Off(args) => cmd_set_mode(NightLightMode::Off, args.temp),
        crate::NightLightCommand::Auto(args) => cmd_set_mode(NightLightMode::Auto, args.temp),
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
        temperature: hyprsunset_current_temperature()
            .or_else(|| parse_temperature_from_args(command_line)),
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
    hypr::dispatch(&["exec", &command])
}

pub(crate) fn stop_hyprsunset() -> crate::Result<()> {
    match Command::new("pkill").args(["-x", "hyprsunset"]).output() {
        Ok(output) if output.status.success() || output.status.code() == Some(1) => Ok(()),
        Ok(output) => Err(command_error("pkill hyprsunset", &output).into()),
        Err(error) => Err(io::Error::new(
            error.kind(),
            format!("failed to run pkill hyprsunset: {error}"),
        )
        .into()),
    }
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
    stream.set_read_timeout(Some(SOCKET_TIMEOUT))?;
    stream.set_write_timeout(Some(SOCKET_TIMEOUT))?;

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
        )
    })
}

fn command_error(label: &str, output: &std::process::Output) -> io::Error {
    let stderr = String::from_utf8_lossy(&output.stderr);
    let stdout = String::from_utf8_lossy(&output.stdout);
    let detail = if stderr.trim().is_empty() {
        stdout.trim()
    } else {
        stderr.trim()
    };
    let detail = if detail.is_empty() {
        format!("exited with status {}", output.status)
    } else {
        detail.to_owned()
    };

    io::Error::other(format!("{label} failed: {detail}"))
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
    stream.set_read_timeout(Some(SOCKET_TIMEOUT))?;
    stream.set_write_timeout(Some(SOCKET_TIMEOUT))?;

    stream.write_all(request.as_bytes())?;
    stream.shutdown(Shutdown::Write)?;

    let mut response = String::new();
    BufReader::new(stream).read_to_string(&mut response)?;
    Ok(response.trim().to_owned())
}

fn hyprsunset_socket_path() -> crate::Result<PathBuf> {
    let root = paths::xdg_runtime_dir()?.join("hypr");

    if let Some(signature) = hyprland_signature() {
        let runtime_path = root.join(&signature).join(".hyprsunset.sock");
        if runtime_path.exists() {
            return Ok(runtime_path);
        }
    }

    let fallback_path = root.join(".hyprsunset.sock");
    if fallback_path.exists() {
        return Ok(fallback_path);
    }

    if let Some(path) = find_hyprsunset_socket_candidates(&root)?
        .into_iter()
        .max_by_key(|(modified, _)| *modified)
        .map(|(_, path)| path)
    {
        return Ok(path);
    }

    if let Some(signature) = hyprland_signature() {
        return Ok(root.join(signature).join(".hyprsunset.sock"));
    }

    Ok(fallback_path)
}

fn hyprland_signature() -> Option<String> {
    env::var("HYPRLAND_INSTANCE_SIGNATURE")
        .ok()
        .filter(|value| !value.is_empty())
}

fn find_hyprsunset_socket_candidates(root: &Path) -> io::Result<Vec<(SystemTime, PathBuf)>> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };

    let mut candidates = Vec::new();
    for entry in entries {
        let entry = entry?;
        let path = entry.path().join(".hyprsunset.sock");
        if !path.exists() {
            continue;
        }

        let modified = fs::metadata(&path)
            .and_then(|metadata| metadata.modified())
            .unwrap_or(UNIX_EPOCH);
        candidates.push((modified, path));
    }

    Ok(candidates)
}

fn parse_temperature_reply(reply: &str) -> crate::Result<i32> {
    reply.trim().parse::<i32>().map_err(|error| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid hyprsunset IPC temperature reply '{reply}': {error}"),
        )
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

    #[test]
    fn parse_temperature_reply_accepts_numeric_responses() {
        assert_eq!(parse_temperature_reply("4300").expect("valid reply"), 4300);
        assert_eq!(
            parse_temperature_reply(" 5100\n").expect("trimmed valid reply"),
            5100
        );
    }

    #[test]
    fn parse_temperature_reply_rejects_non_numeric_responses() {
        assert!(parse_temperature_reply("ok").is_err());
    }

    #[test]
    fn request_envelope_serialization_matches_socket_protocol() {
        let ping = serde_json::to_value(RequestEnvelope::<()> {
            method: "ping".to_owned(),
            params: None,
        })
        .expect("ping request should serialize");
        assert_eq!(ping, serde_json::json!({ "method": "ping" }));

        let set_mode = serde_json::to_value(RequestEnvelope {
            method: METHOD_NIGHT_LIGHT_SET.to_owned(),
            params: Some(NightLightSetParams {
                mode: NightLightMode::On,
                temperature: Some(4500),
            }),
        })
        .expect("set request should serialize");
        assert_eq!(
            set_mode,
            serde_json::json!({
                "method": "night_light.set",
                "params": {
                    "mode": "on",
                    "temperature": 4500,
                },
            })
        );
    }

    #[test]
    fn response_envelope_deserializes_success_and_error_payloads() {
        let success: ResponseEnvelope<NightLightStatus> = serde_json::from_str(
            r#"{"ok":true,"data":{"mode":"auto","running":true,"temperature":4500,"target_temperature":4500,"dark_hint":false,"scheduled_running":true,"scheduled_dark_hint":false}}"#,
        )
        .expect("success response should deserialize");
        assert!(success.ok);
        assert_eq!(success.data.expect("status data").temperature, Some(4500));
        assert!(success.error.is_none());

        let error: ResponseEnvelope<serde_json::Value> =
            serde_json::from_str(r#"{"ok":false,"error":"socket unavailable"}"#)
                .expect("error response should deserialize");
        assert!(!error.ok);
        assert_eq!(error.error.as_deref(), Some("socket unavailable"));
        assert!(error.data.is_none());
    }

    #[test]
    fn socket_unavailable_only_matches_expected_io_errors() {
        assert!(socket_unavailable(&io::Error::new(
            io::ErrorKind::NotFound,
            "missing socket",
        )));
        assert!(socket_unavailable(&io::Error::new(
            io::ErrorKind::ConnectionRefused,
            "refused",
        )));
        assert!(socket_unavailable(&io::Error::new(
            io::ErrorKind::ConnectionReset,
            "reset",
        )));
        assert!(!socket_unavailable(&io::Error::new(
            io::ErrorKind::PermissionDenied,
            "denied",
        )));
        assert!(!socket_unavailable(&io::Error::new(
            io::ErrorKind::AddrInUse,
            "in use",
        )));
        assert!(!socket_unavailable(&io::Error::other("other failure")));
    }
}
