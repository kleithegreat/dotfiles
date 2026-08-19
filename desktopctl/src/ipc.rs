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

use crate::paths;

/// Timeout for requests the daemon answers from memory or quick probes.
pub(crate) const DEFAULT_TIMEOUT: Duration = Duration::from_secs(3);
/// Timeout for requests that block on a full theme apply (hyprctl reloads,
/// dconf, spicetify, possibly a lutgen pass over the wallpaper).
pub(crate) const APPLY_TIMEOUT: Duration = Duration::from_secs(120);

const RETRY_INTERVAL: Duration = Duration::from_millis(200);

pub(crate) mod methods {
    pub const PING: &str = "ping";
    pub const SUBSCRIBE: &str = "subscribe";

    pub const NIGHT_LIGHT_STATUS: &str = "night_light.status";
    pub const NIGHT_LIGHT_SET: &str = "night_light.set";
    pub const NIGHT_LIGHT_TOGGLE: &str = "night_light.toggle";

    pub const THEME_STATUS: &str = "theme.status";
    pub const THEME_SET: &str = "theme.set";
    pub const THEME_APPLY: &str = "theme.apply";
    pub const THEME_PRESET_APPLY: &str = "theme.preset_apply";
    pub const THEME_PRESET_SAVE: &str = "theme.preset_save";
    pub const THEME_PRESET_DELETE: &str = "theme.preset_delete";

    pub const HYPR_INPUT_STATUS: &str = "hypr.input_status";
    pub const HYPR_INPUT_SET: &str = "hypr.input_set";
    pub const HYPR_ANIMATIONS_SAVE: &str = "hypr.animations_save";
    pub const HYPR_ANIMATIONS_CLEAR: &str = "hypr.animations_clear";
    pub const HYPR_KEYBINDS_SAVE: &str = "hypr.keybinds_save";
    pub const HYPR_KEYBINDS_CLEAR: &str = "hypr.keybinds_clear";

    pub const BRIGHTNESS_STATUS: &str = "brightness.status";
    pub const BRIGHTNESS_SET: &str = "brightness.set";
    pub const BRIGHTNESS_STEP: &str = "brightness.step";
    pub const BRIGHTNESS_DIM: &str = "brightness.dim";
    pub const BRIGHTNESS_RESTORE: &str = "brightness.restore";
}

/// Topics a subscriber can select; each event name is `<topic>.<what>`.
pub(crate) const TOPICS: &[&str] = &["theme", "night_light", "brightness", "hypr_input"];

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
         desktop mutations require the running daemon (started from Hyprland autostart)"
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
    use crate::night_light::{NightLightMode, NightLightSetParams, NightLightStatus};

    #[test]
    fn request_envelope_serialization_matches_socket_protocol() {
        let ping = serde_json::to_value(RequestEnvelope::<()> {
            method: "ping".to_owned(),
            params: None,
        })
        .expect("ping request should serialize");
        assert_eq!(ping, serde_json::json!({ "method": "ping" }));

        let set_mode = serde_json::to_value(RequestEnvelope {
            method: methods::NIGHT_LIGHT_SET.to_owned(),
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
    fn event_envelope_is_distinguishable_from_a_response() {
        let event = EventEnvelope {
            event: "theme.changed".to_owned(),
            data: serde_json::json!({ "changed_keys": [] }),
        };
        let value = serde_json::to_value(&event).expect("event should serialize");
        assert!(value.get("event").is_some());
        assert!(value.get("ok").is_none());

        // A response line must never parse as an event and vice versa.
        let response = serde_json::json!({ "ok": true, "data": { "pong": true } });
        assert!(response.get("event").is_none());

        let round_trip: EventEnvelope =
            serde_json::from_value(value).expect("event should deserialize");
        assert_eq!(round_trip.event, "theme.changed");
    }

    #[test]
    fn event_topic_is_the_prefix_before_the_first_dot() {
        let event = EventEnvelope {
            event: "night_light.changed".to_owned(),
            data: serde_json::Value::Null,
        };
        assert_eq!(event.topic(), "night_light");
        assert!(TOPICS.contains(&event.topic()));
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
        let result = send_request_with_retry::<(), serde_json::Value>(
            methods::PING,
            None,
            DEFAULT_TIMEOUT,
            Duration::from_millis(450),
        );
        let elapsed = start.elapsed();

        let error = result.expect_err("no daemon is listening");
        assert!(socket_unavailable(error.as_ref()));
        assert!(elapsed >= Duration::from_millis(400), "retried until deadline");
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

        let response: serde_json::Value = send_request_with_retry::<(), _>(
            methods::PING,
            None,
            DEFAULT_TIMEOUT,
            Duration::from_secs(5),
        )
        .expect("retry should reach the late listener");
        assert_eq!(response, serde_json::json!({ "pong": true }));
        listener.join().expect("listener thread");
    }
}
