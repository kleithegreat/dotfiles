//! Client transport and wire envelopes for the desktopctl daemon socket.
//!
//! The protocol is newline-delimited JSON over a Unix socket. Requests are
//! `{"method": ..., "params"?: ...}`; replies are `{"ok": ..., "data"|"error": ...}`.
//! Server-initiated events use `{"event": ..., "data": ...}` — distinguishable
//! from replies by the `event` key, so a subscribed connection needs no
//! request ids.

use serde::{Deserialize, Serialize, de::DeserializeOwned};
use std::{
    io::{self, BufRead, BufReader, Write},
    os::unix::net::UnixStream,
    path::PathBuf,
    thread,
    time::{Duration, Instant},
};

use crate::{airpods, night_light, paths};

/// Timeout for requests the daemon answers from memory or quick probes.
pub(crate) const DEFAULT_TIMEOUT: Duration = Duration::from_secs(3);
/// Timeout for requests that block on a full theme apply (hyprctl reloads,
/// dconf, possibly a lutgen pass over the wallpaper).
pub(crate) const APPLY_TIMEOUT: Duration = Duration::from_secs(120);

const RETRY_INTERVAL: Duration = Duration::from_millis(200);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum StepDirection {
    Up,
    Down,
}

#[derive(Debug, Clone, PartialEq)]
pub(crate) enum RpcRequest {
    Ping,
    DaemonStatus,
    Subscribe {
        topics: Vec<String>,
    },
    NightLightStatus,
    NightLightSet {
        mode: night_light::NightLightMode,
        temperature: Option<i32>,
    },
    NightLightToggle,
    ThemeStatus,
    ThemeSet {
        key: String,
        value: serde_json::Value,
    },
    ThemeApply {
        scope: String,
        target: Option<String>,
    },
    ThemePresetApply {
        name: String,
    },
    ThemePresetSave {
        name: String,
        payload: serde_json::Value,
    },
    ThemePresetDelete {
        name: String,
    },
    HyprInputStatus,
    HyprInputSet {
        key: String,
        value: String,
    },
    HyprMonitorsStatus,
    HyprMonitorsPrimary {
        selector: String,
    },
    HyprMonitorsLayout {
        outputs: serde_json::Value,
    },
    SessionStatus,
    SessionAutomatic {
        automatic: bool,
    },
    SessionRestore {
        if_automatic: bool,
    },
    BrightnessStatus,
    BrightnessSet {
        device: Option<String>,
        percent: u16,
    },
    BrightnessStep {
        device: Option<String>,
        direction: StepDirection,
    },
    BrightnessDim {
        device: Option<String>,
    },
    BrightnessRestore {
        device: Option<String>,
    },
    AirDropStatus,
    AirDropVisible {
        enabled: bool,
    },
    AirDropAnswer {
        id: u64,
        accept: bool,
    },
    AirDropShare {
        paths: Vec<PathBuf>,
        urls: Vec<String>,
        text: Option<String>,
    },
    AirDropSend {
        receiver: String,
    },
    AirDropCancel,
    AirPodsStatus,
    AirPodsNoise {
        mode: airpods::NoiseMode,
    },
    AirPodsAwareness {
        enabled: bool,
    },
    AirPodsReach {
        reach: airpods::Reach,
    },
    FnLockAnnounce,
}

impl RpcRequest {
    pub(crate) fn into_wire(self) -> (&'static str, Option<serde_json::Value>) {
        use serde_json::json;
        match self {
            Self::Ping => ("ping", None),
            Self::DaemonStatus => ("daemon.status", None),
            Self::Subscribe { topics } => ("subscribe", Some(json!({ "topics": topics }))),
            Self::NightLightStatus => ("night_light.status", None),
            Self::NightLightSet { mode, temperature } => (
                "night_light.set",
                Some(json!({ "mode": mode, "temperature": temperature })),
            ),
            Self::NightLightToggle => ("night_light.toggle", None),
            Self::ThemeStatus => ("theme.status", None),
            Self::ThemeSet { key, value } => {
                ("theme.set", Some(json!({ "key": key, "value": value })))
            }
            Self::ThemeApply { scope, target } => (
                "theme.apply",
                Some(json!({ "scope": scope, "target": target })),
            ),
            Self::ThemePresetApply { name } => {
                ("theme.preset_apply", Some(json!({ "name": name })))
            }
            Self::ThemePresetSave { name, payload } => (
                "theme.preset_save",
                Some(json!({ "name": name, "payload": payload })),
            ),
            Self::ThemePresetDelete { name } => {
                ("theme.preset_delete", Some(json!({ "name": name })))
            }
            Self::HyprInputStatus => ("hypr.input_status", None),
            Self::HyprInputSet { key, value } => (
                "hypr.input_set",
                Some(json!({ "key": key, "value": value })),
            ),
            Self::HyprMonitorsStatus => ("hypr.monitors_status", None),
            Self::HyprMonitorsPrimary { selector } => (
                "hypr.monitors_primary",
                Some(json!({ "selector": selector })),
            ),
            Self::HyprMonitorsLayout { outputs } => {
                ("hypr.monitors_layout", Some(json!({ "outputs": outputs })))
            }
            Self::SessionStatus => ("session.status", None),
            Self::SessionAutomatic { automatic } => {
                ("session.automatic", Some(json!({ "automatic": automatic })))
            }
            Self::SessionRestore { if_automatic } => (
                "session.restore",
                Some(json!({ "if_automatic": if_automatic })),
            ),
            Self::BrightnessStatus => ("brightness.status", None),
            Self::BrightnessSet { device, percent } => (
                "brightness.set",
                Some(json!({ "device": device, "percent": percent })),
            ),
            Self::BrightnessStep { device, direction } => (
                "brightness.step",
                Some(json!({ "device": device, "direction": direction })),
            ),
            Self::BrightnessDim { device } => ("brightness.dim", Some(json!({ "device": device }))),
            Self::BrightnessRestore { device } => {
                ("brightness.restore", Some(json!({ "device": device })))
            }
            Self::AirDropStatus => ("airdrop.status", None),
            Self::AirDropVisible { enabled } => {
                ("airdrop.visible", Some(json!({ "enabled": enabled })))
            }
            Self::AirDropAnswer { id, accept } => (
                "airdrop.answer",
                Some(json!({ "id": id, "accept": accept })),
            ),
            Self::AirDropShare { paths, urls, text } => (
                "airdrop.share",
                Some(json!({ "paths": paths, "urls": urls, "text": text })),
            ),
            Self::AirDropSend { receiver } => {
                ("airdrop.send", Some(json!({ "receiver": receiver })))
            }
            Self::AirDropCancel => ("airdrop.cancel", None),
            Self::AirPodsStatus => ("airpods.status", None),
            Self::AirPodsNoise { mode } => ("airpods.noise", Some(json!({ "mode": mode }))),
            Self::AirPodsAwareness { enabled } => {
                ("airpods.awareness", Some(json!({ "enabled": enabled })))
            }
            Self::AirPodsReach { reach } => ("airpods.reach", Some(json!({ "reach": reach }))),
            Self::FnLockAnnounce => ("fn_lock.announce", None),
        }
    }

    pub(crate) fn from_wire(
        method: &str,
        params: serde_json::Value,
    ) -> std::result::Result<Self, String> {
        fn de<T: DeserializeOwned>(
            method: &str,
            value: serde_json::Value,
        ) -> std::result::Result<T, String> {
            serde_json::from_value(value)
                .map_err(|error| format!("invalid params for {method}: {error}"))
        }
        fn de_default<T: DeserializeOwned>(
            method: &str,
            value: serde_json::Value,
        ) -> std::result::Result<T, String> {
            let value = if value.is_null() {
                serde_json::Value::Object(Default::default())
            } else {
                value
            };
            de(method, value)
        }

        Ok(match method {
            "ping" => Self::Ping,
            "daemon.status" => Self::DaemonStatus,
            "subscribe" => {
                #[derive(Default, Deserialize)]
                #[serde(default)]
                struct P {
                    topics: Vec<String>,
                }
                let p: P = de_default(method, params)?;
                Self::Subscribe { topics: p.topics }
            }
            "night_light.status" => Self::NightLightStatus,
            "night_light.set" => {
                #[derive(Deserialize)]
                struct P {
                    mode: night_light::NightLightMode,
                    #[serde(default)]
                    temperature: Option<i32>,
                }
                let p: P = de(method, params)?;
                Self::NightLightSet {
                    mode: p.mode,
                    temperature: p.temperature,
                }
            }
            "night_light.toggle" => Self::NightLightToggle,
            "theme.status" => Self::ThemeStatus,
            "theme.set" => {
                #[derive(Deserialize)]
                struct P {
                    key: String,
                    value: serde_json::Value,
                }
                let p: P = de(method, params)?;
                Self::ThemeSet {
                    key: p.key,
                    value: p.value,
                }
            }
            "theme.apply" => {
                #[derive(Deserialize)]
                struct P {
                    scope: String,
                    #[serde(default)]
                    target: Option<String>,
                }
                let p: P = de(method, params)?;
                Self::ThemeApply {
                    scope: p.scope,
                    target: p.target,
                }
            }
            "theme.preset_apply" => {
                #[derive(Deserialize)]
                struct P {
                    name: String,
                }
                let p: P = de(method, params)?;
                Self::ThemePresetApply { name: p.name }
            }
            "theme.preset_save" => {
                #[derive(Deserialize)]
                struct P {
                    name: String,
                    payload: serde_json::Value,
                }
                let p: P = de(method, params)?;
                Self::ThemePresetSave {
                    name: p.name,
                    payload: p.payload,
                }
            }
            "theme.preset_delete" => {
                #[derive(Deserialize)]
                struct P {
                    name: String,
                }
                let p: P = de(method, params)?;
                Self::ThemePresetDelete { name: p.name }
            }
            "hypr.input_status" => Self::HyprInputStatus,
            "hypr.input_set" => {
                #[derive(Deserialize)]
                struct P {
                    key: String,
                    value: String,
                }
                let p: P = de(method, params)?;
                Self::HyprInputSet {
                    key: p.key,
                    value: p.value,
                }
            }
            "hypr.monitors_status" => Self::HyprMonitorsStatus,
            "hypr.monitors_primary" => {
                #[derive(Deserialize)]
                struct P {
                    selector: String,
                }
                let p: P = de(method, params)?;
                Self::HyprMonitorsPrimary {
                    selector: p.selector,
                }
            }
            "hypr.monitors_layout" => {
                #[derive(Deserialize)]
                struct P {
                    outputs: serde_json::Value,
                }
                let p: P = de(method, params)?;
                Self::HyprMonitorsLayout { outputs: p.outputs }
            }
            "session.status" => Self::SessionStatus,
            "session.automatic" => {
                #[derive(Deserialize)]
                struct P {
                    automatic: bool,
                }
                let p: P = de(method, params)?;
                Self::SessionAutomatic {
                    automatic: p.automatic,
                }
            }
            "session.restore" => {
                #[derive(Default, Deserialize)]
                #[serde(default)]
                struct P {
                    if_automatic: bool,
                }
                let p: P = de_default(method, params)?;
                Self::SessionRestore {
                    if_automatic: p.if_automatic,
                }
            }
            "brightness.status" => Self::BrightnessStatus,
            "brightness.set" => {
                #[derive(Deserialize)]
                struct P {
                    #[serde(default)]
                    device: Option<String>,
                    percent: u16,
                }
                let p: P = de(method, params)?;
                Self::BrightnessSet {
                    device: p.device,
                    percent: p.percent,
                }
            }
            "brightness.step" => {
                #[derive(Deserialize)]
                struct P {
                    #[serde(default)]
                    device: Option<String>,
                    direction: StepDirection,
                }
                let p: P = de(method, params)?;
                Self::BrightnessStep {
                    device: p.device,
                    direction: p.direction,
                }
            }
            "brightness.dim" => {
                #[derive(Default, Deserialize)]
                #[serde(default)]
                struct P {
                    device: Option<String>,
                }
                let p: P = de_default(method, params)?;
                Self::BrightnessDim { device: p.device }
            }
            "brightness.restore" => {
                #[derive(Default, Deserialize)]
                #[serde(default)]
                struct P {
                    device: Option<String>,
                }
                let p: P = de_default(method, params)?;
                Self::BrightnessRestore { device: p.device }
            }
            "airdrop.status" => Self::AirDropStatus,
            "airdrop.visible" => {
                #[derive(Deserialize)]
                struct P {
                    enabled: bool,
                }
                let p: P = de(method, params)?;
                Self::AirDropVisible { enabled: p.enabled }
            }
            "airdrop.answer" => {
                #[derive(Deserialize)]
                struct P {
                    id: u64,
                    accept: bool,
                }
                let p: P = de(method, params)?;
                Self::AirDropAnswer {
                    id: p.id,
                    accept: p.accept,
                }
            }
            "airdrop.share" => {
                #[derive(Default, Deserialize)]
                #[serde(default)]
                struct P {
                    paths: Vec<PathBuf>,
                    urls: Vec<String>,
                    text: Option<String>,
                }
                let p: P = de_default(method, params)?;
                Self::AirDropShare {
                    paths: p.paths,
                    urls: p.urls,
                    text: p.text,
                }
            }
            "airdrop.send" => {
                #[derive(Deserialize)]
                struct P {
                    receiver: String,
                }
                let p: P = de(method, params)?;
                Self::AirDropSend {
                    receiver: p.receiver,
                }
            }
            "airdrop.cancel" => Self::AirDropCancel,
            "airpods.status" => Self::AirPodsStatus,
            "airpods.noise" => {
                #[derive(Deserialize)]
                struct P {
                    mode: airpods::NoiseMode,
                }
                let p: P = de(method, params)?;
                Self::AirPodsNoise { mode: p.mode }
            }
            "airpods.awareness" => {
                #[derive(Deserialize)]
                struct P {
                    enabled: bool,
                }
                let p: P = de(method, params)?;
                Self::AirPodsAwareness { enabled: p.enabled }
            }
            "airpods.reach" => {
                #[derive(Deserialize)]
                struct P {
                    reach: airpods::Reach,
                }
                let p: P = de(method, params)?;
                Self::AirPodsReach { reach: p.reach }
            }
            "fn_lock.announce" => Self::FnLockAnnounce,
            _ => return Err(format!("unsupported method: {method}")),
        })
    }
}

/// Topics a subscriber can select; each event name is `<topic>.<what>`.
pub(crate) const TOPICS: &[&str] = &[
    "theme",
    "night_light",
    "brightness",
    "hypr_input",
    "hypr_monitors",
    "session",
    "airpods",
    "airdrop",
    "fn_lock",
    "power",
    "focus",
    "daemon",
];

#[derive(Debug, Serialize)]
pub(crate) struct RequestEnvelope<P> {
    pub method: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub params: Option<P>,
}

#[derive(Debug, Deserialize)]
pub(crate) struct ResponseEnvelope<T> {
    pub ok: bool,
    pub data: Option<T>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub(crate) struct EventEnvelope {
    pub event: String,
    pub data: serde_json::Value,
}

impl EventEnvelope {
    /// The topic prefix of the event name (`theme.changed` -> `theme`).
    pub fn topic(&self) -> &str {
        self.event.split('.').next().unwrap_or(&self.event)
    }
}

pub(crate) fn socket_path() -> crate::Result<PathBuf> {
    Ok(paths::xdg_runtime_dir()?.join("desktopctl.sock"))
}

/// The strict-mode failure message for mutations when the daemon is down.
pub(crate) fn daemon_unavailable_message(cause: &dyn std::fmt::Display) -> String {
    let socket = socket_path()
        .map(|path| path.display().to_string())
        .unwrap_or_else(|_| "$XDG_RUNTIME_DIR/desktopctl.sock".to_owned());
    format!(
        "desktopctl daemon is unavailable at {socket}: {cause}; \
         desktop mutations require the running daemon (`systemctl --user status desktopctl.service`)"
    )
}

pub(crate) fn send_request<P, T>(
    method: &str,
    params: Option<P>,
    timeout: Duration,
) -> crate::Result<T>
where
    P: Serialize,
    T: DeserializeOwned,
{
    let socket_path = socket_path()?;
    let mut stream = UnixStream::connect(&socket_path).map_err(|error| {
        io::Error::new(
            error.kind(),
            format!("failed to connect to {}: {error}", socket_path.display()),
        )
    })?;
    stream.set_read_timeout(Some(timeout))?;
    stream.set_write_timeout(Some(timeout))?;

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
            crate::invalid_data(format!("invalid response from desktopctl daemon: {error}"))
        })?;

    if response.ok {
        return response.data.ok_or_else(|| {
            crate::invalid_data("desktopctl daemon returned success without data").into()
        });
    }

    Err(io::Error::other(
        response
            .error
            .unwrap_or_else(|| "desktopctl daemon request failed".to_owned()),
    )
    .into())
}

/// `send_request`, but retrying connect failures until `wait` has elapsed.
/// Only daemon-absent failures retry; a reachable daemon's error is final.
pub(crate) fn send_request_with_retry<P, T>(
    method: &str,
    params: Option<P>,
    timeout: Duration,
    wait: Duration,
) -> crate::Result<T>
where
    P: Serialize + Clone,
    T: DeserializeOwned,
{
    let deadline = Instant::now() + wait;
    loop {
        match send_request(method, params.clone(), timeout) {
            Err(error) if socket_unavailable(error.as_ref()) && Instant::now() < deadline => {
                thread::sleep(RETRY_INTERVAL);
            }
            result => return result,
        }
    }
}

/// A daemon mutation: retries while the daemon is absent, then reports its
/// absence as the strict-mode failure instead of the raw connect error.
pub(crate) fn mutate<T: DeserializeOwned>(
    request: RpcRequest,
    timeout: Duration,
    wait: Duration,
) -> crate::Result<T> {
    let (method, params) = request.into_wire();
    send_request_with_retry(method, params, timeout, wait).map_err(|error| {
        if socket_unavailable(error.as_ref()) {
            io::Error::other(daemon_unavailable_message(&error)).into()
        } else {
            error
        }
    })
}

pub(crate) fn send<T: DeserializeOwned>(
    request: RpcRequest,
    timeout: Duration,
) -> crate::Result<T> {
    let (method, params) = request.into_wire();
    send_request(method, params, timeout)
}

pub(crate) fn stream_events(
    topics: Vec<String>,
    mut on_event: impl FnMut(&str) -> crate::Result<bool>,
) -> crate::Result<()> {
    let socket_path = socket_path()?;
    let mut stream = UnixStream::connect(&socket_path).map_err(|error| {
        if matches!(
            error.kind(),
            io::ErrorKind::NotFound
                | io::ErrorKind::ConnectionRefused
                | io::ErrorKind::ConnectionReset
        ) {
            io::Error::new(error.kind(), daemon_unavailable_message(&error))
        } else {
            error
        }
    })?;
    stream.set_write_timeout(Some(DEFAULT_TIMEOUT))?;
    let (method, params) = RpcRequest::Subscribe { topics }.into_wire();
    let payload = RequestEnvelope {
        method: method.to_owned(),
        params,
    };
    let line = serde_json::to_string(&payload)?;
    stream.write_all(line.as_bytes())?;
    stream.write_all(b"\n")?;
    stream.flush()?;

    let mut reader = BufReader::new(stream);
    let mut ack = String::new();
    if reader.read_line(&mut ack)? == 0 {
        return Err(crate::invalid_data("daemon closed connection before subscribe reply").into());
    }
    let response: ResponseEnvelope<serde_json::Value> = serde_json::from_str(ack.trim_end())
        .map_err(|error| crate::invalid_data(format!("invalid subscribe reply: {error}")))?;
    if !response.ok {
        return Err(io::Error::other(
            response
                .error
                .unwrap_or_else(|| "subscribe failed".to_owned()),
        )
        .into());
    }

    let mut event_line = String::new();
    loop {
        event_line.clear();
        if reader.read_line(&mut event_line)? == 0 {
            return Ok(());
        }
        let trimmed = event_line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if !on_event(trimmed)? {
            return Ok(());
        }
    }
}

pub(crate) fn socket_unavailable(error: &(dyn std::error::Error + 'static)) -> bool {
    error.downcast_ref::<io::Error>().is_some_and(|io_error| {
        matches!(
            io_error.kind(),
            io::ErrorKind::NotFound
                | io::ErrorKind::ConnectionRefused
                | io::ErrorKind::ConnectionReset
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn send_request_with_retry_gives_up_after_the_deadline() {
        let _lock = crate::test_support::env_lock();
        let temp =
            crate::test_support::TempDir::new("desktopctl-ipc-retry").expect("create temp dir");
        let _runtime = crate::test_support::ScopedEnvVar::set(
            "XDG_RUNTIME_DIR",
            temp.path().to_str().expect("temp path utf-8"),
        );

        let start = Instant::now();
        let (ping_method, ping_params) = RpcRequest::Ping.into_wire();
        let result = send_request_with_retry::<_, serde_json::Value>(
            ping_method,
            ping_params,
            DEFAULT_TIMEOUT,
            Duration::from_millis(450),
        );
        let elapsed = start.elapsed();

        let error = result.expect_err("no daemon is listening");
        assert!(socket_unavailable(error.as_ref()));
        assert!(
            elapsed >= Duration::from_millis(400),
            "retried until deadline"
        );
    }

    #[test]
    fn send_request_with_retry_succeeds_once_a_listener_appears() {
        let _lock = crate::test_support::env_lock();
        let temp =
            crate::test_support::TempDir::new("desktopctl-ipc-late").expect("create temp dir");
        let _runtime = crate::test_support::ScopedEnvVar::set(
            "XDG_RUNTIME_DIR",
            temp.path().to_str().expect("temp path utf-8"),
        );

        let socket = temp.path().join("desktopctl.sock");
        let listener_socket = socket.clone();
        let listener = thread::spawn(move || {
            // Appear late: the client should be retrying by the time we bind.
            thread::sleep(Duration::from_millis(300));
            let listener =
                std::os::unix::net::UnixListener::bind(&listener_socket).expect("bind socket");
            let (mut stream, _) = listener.accept().expect("accept client");
            let mut line = String::new();
            BufReader::new(&stream)
                .read_line(&mut line)
                .expect("read request");
            stream
                .write_all(b"{\"ok\":true,\"data\":{\"pong\":true}}\n")
                .expect("write response");
        });

        let (ping_method, ping_params) = RpcRequest::Ping.into_wire();
        let response: serde_json::Value = send_request_with_retry::<_, _>(
            ping_method,
            ping_params,
            DEFAULT_TIMEOUT,
            Duration::from_secs(5),
        )
        .expect("retry should reach the late listener");
        assert_eq!(response, serde_json::json!({ "pong": true }));
        listener.join().expect("listener thread");
    }
}
