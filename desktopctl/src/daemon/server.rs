use crate::{
    daemon::{
        SubsystemHealth,
        airdrop::AirDropController,
        airpods::AirPodsController,
        brightness::BrightnessController,
        focus::FocusState,
        hypr::HyprController,
        night_light::Controller,
        power::PowerHistory,
        session::SessionController,
        theme::{ThemeController, ThemeJob},
    },
    ipc::{self, EventEnvelope, RpcRequest, StepDirection},
    theme::{ApplyScope, DarkHintOrigin},
};
use serde::Deserialize;
use std::{io, os::unix::fs::FileTypeExt, path::Path, sync::Arc, time::Instant};
use tokio::{
    fs,
    io::{AsyncBufRead, AsyncBufReadExt, AsyncReadExt, AsyncWrite, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::{broadcast, watch},
};

const MAX_IPC_LINE_BYTES: usize = 256 * 1024;

#[derive(Debug, Deserialize)]
struct Request {
    method: String,
    #[serde(default)]
    params: serde_json::Value,
}

/// Fan-out handle for daemon-side change events. Controllers publish after a
/// successful commit; subscribed connections forward matching events.
#[derive(Clone)]
pub struct Events {
    sender: broadcast::Sender<Arc<EventEnvelope>>,
}

impl Events {
    pub fn new() -> Self {
        let (sender, _) = broadcast::channel(64);
        Self { sender }
    }

    pub fn publish(&self, event: &str, data: serde_json::Value) {
        // Subscribers only receive listed topics; an unlisted one vanishes silently.
        debug_assert!(
            ipc::TOPICS.contains(&event.split('.').next().unwrap_or(event)),
            "{event} is not in ipc::TOPICS"
        );
        // A send error only means no subscriber is connected right now.
        let _ = self.sender.send(Arc::new(EventEnvelope {
            event: event.to_owned(),
            data,
        }));
    }

    pub fn subscriber_count(&self) -> usize {
        self.sender.receiver_count()
    }

    pub(super) fn receiver(&self) -> broadcast::Receiver<Arc<EventEnvelope>> {
        self.sender.subscribe()
    }
}

/// Everything a client connection can reach.
#[derive(Clone)]
pub struct ServerContext {
    pub airdrop: AirDropController,
    pub airpods: AirPodsController,
    pub night_light: Controller,
    pub theme: ThemeController,
    pub hypr: HyprController,
    pub session: SessionController,
    pub brightness: BrightnessController,
    pub power: PowerHistory,
    pub focus: FocusState,
    pub health: SubsystemHealth,
    pub started_at: Instant,
    pub events: Events,
}

pub async fn run(context: ServerContext, mut shutdown: watch::Receiver<bool>) -> crate::Result<()> {
    let socket_path = ipc::socket_path()?;
    prepare_socket_path(&socket_path).await?;
    let listener = UnixListener::bind(&socket_path)?;

    let result = async {
        loop {
            tokio::select! {
                changed = shutdown.changed() => {
                    if changed.is_err() || *shutdown.borrow() {
                        return Ok(());
                    }
                }
                accepted = listener.accept() => {
                    match accepted {
                        Ok((stream, _)) => {
                            let context = context.clone();
                            tokio::spawn(async move {
                                let _ = handle_client(stream, context).await;
                            });
                        }
                        // A transient accept failure (ECONNABORTED, EMFILE) must not end the daemon.
                        Err(error) => {
                            eprintln!("desktopctl socket accept failed: {error}");
                            tokio::time::sleep(std::time::Duration::from_millis(100)).await;
                        }
                    }
                }
            }
        }
    }
    .await;

    let _ = fs::remove_file(&socket_path).await;
    result
}

async fn prepare_socket_path(path: &Path) -> io::Result<()> {
    let metadata = match fs::metadata(path).await {
        Ok(metadata) => metadata,
        Err(_) => return Ok(()),
    };

    if !metadata.file_type().is_socket() {
        return Err(io::Error::new(
            io::ErrorKind::AlreadyExists,
            format!("refusing to remove non-socket path: {}", path.display()),
        ));
    }

    match UnixStream::connect(path).await {
        Ok(_) => Err(io::Error::new(
            io::ErrorKind::AddrInUse,
            format!("socket already in use: {}", path.display()),
        )),
        Err(error) => match error.kind() {
            io::ErrorKind::NotFound => Ok(()),
            io::ErrorKind::ConnectionRefused | io::ErrorKind::ConnectionReset => {
                fs::remove_file(path).await
            }
            kind => Err(io::Error::new(
                kind,
                format!(
                    "failed to probe existing socket {}: {error}",
                    path.display()
                ),
            )),
        },
    }
}

async fn read_bounded_line<R: AsyncBufRead + Unpin>(
    reader: &mut R,
    max_bytes: usize,
) -> io::Result<Option<String>> {
    let mut buffer = Vec::new();
    let bytes_read = reader
        .take((max_bytes + 1) as u64)
        .read_until(b'\n', &mut buffer)
        .await?;
    if bytes_read == 0 {
        return Ok(None);
    }
    if buffer.len() > max_bytes {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            format!("IPC line exceeds {max_bytes} bytes"),
        ));
    }
    String::from_utf8(buffer)
        .map(Some)
        .map_err(|error| io::Error::new(io::ErrorKind::InvalidData, error))
}

async fn handle_client(stream: UnixStream, context: ServerContext) -> io::Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut reader = BufReader::new(reader);

    loop {
        let line = match read_bounded_line(&mut reader, MAX_IPC_LINE_BYTES).await {
            Ok(Some(line)) => line,
            Ok(None) => break,
            Err(error) => {
                let _ = write_error(&mut writer, error.to_string()).await;
                return Ok(());
            }
        };
        if line.trim().is_empty() {
            continue;
        }

        let wire = match serde_json::from_str::<Request>(&line) {
            Ok(request) => request,
            Err(error) => {
                write_error(&mut writer, format!("invalid request: {error}")).await?;
                continue;
            }
        };

        let rpc = match RpcRequest::from_wire(&wire.method, wire.params) {
            Ok(rpc) => rpc,
            Err(message) => {
                write_error(&mut writer, message).await?;
                continue;
            }
        };

        if let RpcRequest::Subscribe { topics } = rpc {
            let topics = match resolve_topics(topics) {
                Ok(topics) => topics,
                Err(message) => {
                    write_error(&mut writer, message).await?;
                    continue;
                }
            };
            // Subscribe before replying, so no event between the two is lost.
            let receiver = context.events.receiver();
            write_ok(&mut writer, serde_json::json!({ "subscribed": topics })).await?;
            return run_subscription(&mut writer, &mut reader, topics, context, receiver).await;
        }

        match respond(rpc, &context).await {
            Ok(data) => write_ok(&mut writer, data).await?,
            Err(message) => write_error(&mut writer, message).await?,
        }
    }

    Ok(())
}

async fn respond(rpc: RpcRequest, context: &ServerContext) -> Result<serde_json::Value, String> {
    match rpc {
        RpcRequest::Ping => Ok(serde_json::json!({ "pong": true })),
        RpcRequest::DaemonStatus => Ok(daemon_status_value(context)),
        RpcRequest::Subscribe { .. } => Err("subscribe already handled".to_owned()),
        RpcRequest::NightLightStatus => {
            let controller = context.night_light.clone();
            blocking(move || controller.status()).await
        }
        RpcRequest::NightLightSet { mode, temperature } => {
            let controller = context.night_light.clone();
            blocking(move || controller.set_mode(mode, temperature)).await
        }
        RpcRequest::NightLightToggle => {
            let controller = context.night_light.clone();
            blocking(move || controller.toggle()).await
        }
        RpcRequest::ThemeStatus => {
            blocking(|| {
                crate::theme::resolve::load_state().map(|state| crate::theme::state_json(&state))
            })
            .await
        }
        RpcRequest::ThemeSet { key, value } => {
            let job = ThemeJob::Set {
                key,
                value,
                // User-initiated; the schedule bypasses this method.
                origin: DarkHintOrigin::Manual,
            };
            to_value(context.theme.request(job).await)
        }
        RpcRequest::ThemeApply { scope, target } => {
            let scope = ApplyScope::parse(&scope, target).map_err(|error| error.to_string())?;
            to_value(context.theme.request(ThemeJob::Apply { scope }).await)
        }
        RpcRequest::ThemePresetApply { name } => {
            to_value(context.theme.request(ThemeJob::PresetApply { name }).await)
        }
        RpcRequest::ThemePresetSave { name, payload } => {
            let job = ThemeJob::PresetSave { name, payload };
            to_value(context.theme.request(job).await)
        }
        RpcRequest::ThemePresetDelete { name } => {
            to_value(context.theme.request(ThemeJob::PresetDelete { name }).await)
        }
        RpcRequest::HyprInputStatus => {
            let hypr = context.hypr.clone();
            blocking(move || hypr.input_status()).await
        }
        RpcRequest::HyprInputSet { key, value } => {
            let hypr = context.hypr.clone();
            blocking(move || hypr.input_set(&key, &value)).await
        }
        RpcRequest::HyprMonitorsStatus => {
            let hypr = context.hypr.clone();
            blocking(move || hypr.monitors_status()).await
        }
        RpcRequest::HyprMonitorsPrimary { selector } => {
            let hypr = context.hypr.clone();
            blocking(move || hypr.monitors_primary(&selector)).await
        }
        RpcRequest::HyprMonitorsLayout { outputs } => {
            let hypr = context.hypr.clone();
            blocking(move || hypr.monitors_layout(&outputs)).await
        }
        RpcRequest::SessionStatus => to_value(context.session.status()),
        RpcRequest::SessionAutomatic { automatic } => {
            to_value(context.session.set_automatic(automatic))
        }
        RpcRequest::SessionRestore { if_automatic } => {
            let session = context.session.clone();
            blocking(move || session.restore(if_automatic)).await
        }
        RpcRequest::BrightnessStatus => {
            let brightness = context.brightness.clone();
            blocking(move || brightness.status()).await
        }
        RpcRequest::BrightnessSet { device, percent } => {
            let brightness = context.brightness.clone();
            blocking(move || brightness.set(device.as_deref(), percent)).await
        }
        RpcRequest::BrightnessStep { device, direction } => {
            let step = match direction {
                StepDirection::Up => 1.0,
                StepDirection::Down => -1.0,
            };
            let brightness = context.brightness.clone();
            blocking(move || brightness.step(device.as_deref(), step)).await
        }
        RpcRequest::BrightnessDim { device } => {
            let brightness = context.brightness.clone();
            blocking(move || brightness.dim(device.as_deref())).await
        }
        RpcRequest::BrightnessRestore { device } => {
            let brightness = context.brightness.clone();
            blocking(move || brightness.restore(device.as_deref())).await
        }
        RpcRequest::AirDropStatus => to_value(context.airdrop.status()),
        RpcRequest::AirDropVisible { enabled } => to_value(context.airdrop.visible(enabled).await),
        RpcRequest::AirDropAnswer { id, accept } => {
            to_value(context.airdrop.answer(id, accept).await)
        }
        RpcRequest::AirDropShare { paths, urls, text } => {
            to_value(context.airdrop.share(paths, urls, text).await)
        }
        RpcRequest::AirDropSend { receiver } => to_value(context.airdrop.send(receiver).await),
        RpcRequest::AirDropCancel => to_value(context.airdrop.cancel().await),
        RpcRequest::AirPodsStatus => to_value(context.airpods.status()),
        RpcRequest::AirPodsNoise { mode } => to_value(context.airpods.set_noise(mode).await),
        RpcRequest::AirPodsAwareness { enabled } => {
            to_value(context.airpods.set_awareness(enabled).await)
        }
        RpcRequest::FnLockAnnounce => to_value(
            crate::fn_lock::media_keys()
                .map(|media_keys| {
                    context.events.publish(
                        "fn_lock.changed",
                        serde_json::json!({ "media_keys": media_keys, "osd": true }),
                    );
                    serde_json::Value::Object(Default::default())
                })
                .map_err(Into::into),
        ),
        RpcRequest::AirPodsReach { reach } => to_value(context.airpods.set_reach(reach)),
    }
}

fn daemon_status_value(context: &ServerContext) -> serde_json::Value {
    serde_json::json!({
        "pid": std::process::id(),
        "uptime_secs": context.started_at.elapsed().as_secs(),
        "subsystems": context.health.snapshot(),
        "subscribers": context.events.subscriber_count(),
    })
}

async fn blocking<T, F>(task: F) -> Result<serde_json::Value, String>
where
    T: serde::Serialize + Send + 'static,
    F: FnOnce() -> crate::Result<T> + Send + 'static,
{
    tokio::task::spawn_blocking(task)
        .await
        .map_err(|error| error.to_string())
        .and_then(to_value)
}

fn to_value<T: serde::Serialize>(result: crate::Result<T>) -> Result<serde_json::Value, String> {
    result
        .map_err(|error| error.to_string())
        .and_then(|data| serde_json::to_value(data).map_err(|error| error.to_string()))
}

fn resolve_topics(requested: Vec<String>) -> Result<Vec<String>, String> {
    if requested.is_empty() {
        return Ok(ipc::TOPICS
            .iter()
            .map(|topic| (*topic).to_owned())
            .collect());
    }

    let mut invalid = Vec::new();
    let mut resolved = Vec::new();
    for topic in requested {
        if !ipc::TOPICS.contains(&topic.as_str()) {
            invalid.push(topic);
        } else if !resolved.contains(&topic) {
            resolved.push(topic);
        }
    }
    if !invalid.is_empty() {
        return Err(format!(
            "unknown subscription topics: {}",
            invalid.join(", ")
        ));
    }
    Ok(resolved)
}

/// After a `subscribe` reply the connection becomes push-only: snapshots for
/// each topic first, then matching events as controllers publish them. The
/// read half is drained only to notice EOF; further requests are refused.
async fn run_subscription<W, R>(
    writer: &mut W,
    reader: &mut BufReader<R>,
    topics: Vec<String>,
    context: ServerContext,
    mut receiver: broadcast::Receiver<Arc<EventEnvelope>>,
) -> io::Result<()>
where
    W: AsyncWrite + Unpin,
    R: tokio::io::AsyncRead + Unpin,
{
    push_snapshots(writer, &topics, &context).await?;

    loop {
        tokio::select! {
            event = receiver.recv() => match event {
                Ok(event) => {
                    if topics.iter().any(|topic| topic == event.topic()) {
                        write_event(writer, &event).await?;
                    }
                }
                Err(broadcast::error::RecvError::Lagged(_)) => {
                    // Dropped events cannot be replayed; resync via snapshots.
                    push_snapshots(writer, &topics, &context).await?;
                }
                Err(broadcast::error::RecvError::Closed) => return Ok(()),
            },
            line = read_bounded_line(reader, MAX_IPC_LINE_BYTES) => match line? {
                None => return Ok(()),
                Some(line) if line.trim().is_empty() => {}
                Some(_) => {
                    write_error(
                        writer,
                        "connection is subscribed; open a new connection for requests".to_owned(),
                    )
                    .await?;
                }
            },
        }
    }
}

async fn push_snapshots<W: AsyncWrite + Unpin>(
    writer: &mut W,
    topics: &[String],
    context: &ServerContext,
) -> io::Result<()> {
    for topic in topics {
        let snapshot = match topic.as_str() {
            "night_light" => {
                let controller = context.night_light.clone();
                blocking(move || controller.status()).await
            }
            "theme" => {
                if let Ok(state) = blocking(|| {
                    crate::theme::resolve::load_state().map(|state| {
                        serde_json::json!({
                            "state": crate::theme::state_json(&state),
                            "changed_keys": [],
                        })
                    })
                })
                .await
                {
                    write_event(
                        writer,
                        &EventEnvelope {
                            event: "theme.changed".to_owned(),
                            data: state,
                        },
                    )
                    .await?;
                }
                if let Ok(presets) = blocking(crate::theme::preset_names).await {
                    write_event(
                        writer,
                        &EventEnvelope {
                            event: "theme.presets_changed".to_owned(),
                            data: serde_json::json!({ "presets": presets }),
                        },
                    )
                    .await?;
                }
                continue;
            }
            "hypr_input" => {
                let hypr = context.hypr.clone();
                blocking(move || hypr.input_status()).await
            }
            "hypr_monitors" => {
                let hypr = context.hypr.clone();
                blocking(move || hypr.monitors_status()).await
            }
            "session" => to_value(context.session.status()),
            "airpods" => to_value(context.airpods.status()),
            "airdrop" => to_value(context.airdrop.status()),
            "power" => match context.power.latest() {
                Some(summary) => Ok(summary),
                None => continue,
            },
            "focus" => match context.focus.latest() {
                Some(summary) => Ok(summary),
                None => continue,
            },
            "daemon" => Ok(daemon_status_value(context)),
            // Absent on hosts without the firmware attribute, so no indicator there.
            "fn_lock" => to_value(
                crate::fn_lock::media_keys()
                    .map(|media_keys| serde_json::json!({ "media_keys": media_keys }))
                    .map_err(Into::into),
            ),
            "brightness" => {
                if let Ok(devices) = blocking(crate::brightness::backlight_snapshot).await {
                    write_brightness_snapshot(writer, devices).await?;
                }
                continue;
            }
            _ => continue,
        };
        if let Ok(data) = snapshot {
            let event = EventEnvelope {
                event: format!("{topic}.changed"),
                data,
            };
            write_event(writer, &event).await?;
        }
    }

    // DDC enumeration (~1s) follows the cheap topics so nothing waits on it.
    if topics.iter().any(|topic| topic == "brightness")
        && let Ok(devices) = blocking(crate::brightness::ddc_snapshot).await
    {
        write_brightness_snapshot(writer, devices).await?;
    }

    Ok(())
}

async fn write_brightness_snapshot<W: AsyncWrite + Unpin>(
    writer: &mut W,
    devices: serde_json::Value,
) -> io::Result<()> {
    if devices.as_array().is_none_or(|devices| devices.is_empty()) {
        return Ok(());
    }

    let event = EventEnvelope {
        event: "brightness.changed".to_owned(),
        data: serde_json::json!({ "devices": devices, "osd": false }),
    };
    write_event(writer, &event).await
}

async fn write_event<W: AsyncWrite + Unpin>(
    writer: &mut W,
    event: &EventEnvelope,
) -> io::Result<()> {
    let payload = serde_json::to_string(event)?;
    writer.write_all(payload.as_bytes()).await?;
    writer.write_all(b"\n").await
}

async fn write_ok<T: serde::Serialize, W: AsyncWrite + Unpin>(
    writer: &mut W,
    data: T,
) -> io::Result<()> {
    let response = serde_json::json!({
        "ok": true,
        "data": data,
    });
    writer.write_all(response.to_string().as_bytes()).await?;
    writer.write_all(b"\n").await
}

async fn write_error<W: AsyncWrite + Unpin>(writer: &mut W, error: String) -> io::Result<()> {
    let response = serde_json::json!({
        "ok": false,
        "error": error,
    });
    writer.write_all(response.to_string().as_bytes()).await?;
    writer.write_all(b"\n").await
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::{
        io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
        net::UnixStream,
    };

    #[tokio::test]
    async fn handle_client_handles_valid_and_malformed_requests() {
        let oversized = format!(
            "{{\"method\":\"ping\",\"pad\":\"{}\"}}",
            "x".repeat(MAX_IPC_LINE_BYTES)
        );
        let responses = send_requests(&[
            "",
            r#"{"method":"ping"}"#,
            "{not valid json",
            r#"{"method":"night_light.set","params":{"mode":"invalid"}}"#,
            r#"{"method":"unknown.method"}"#,
            r#"{"method":"subscribe","params":{"topics":["bogus"]}}"#,
        ])
        .await;

        assert_eq!(responses.len(), 5);
        assert_eq!(
            responses[0],
            serde_json::json!({ "ok": true, "data": { "pong": true } })
        );
        assert!(
            responses[1]["error"]
                .as_str()
                .expect("error")
                .starts_with("invalid request:")
        );
        assert!(
            responses[2]["error"]
                .as_str()
                .expect("error")
                .starts_with("invalid params for night_light.set:")
        );
        assert_eq!(
            responses[3],
            serde_json::json!({ "ok": false, "error": "unsupported method: unknown.method" })
        );
        assert_eq!(responses[4]["ok"], serde_json::json!(false));

        let capped = send_requests(&[&oversized]).await;
        assert_eq!(capped.len(), 1);
        assert_eq!(capped[0]["ok"], serde_json::json!(false));
    }

    async fn send_requests(requests: &[&str]) -> Vec<serde_json::Value> {
        let (client, server) = UnixStream::pair().expect("socket pair");
        let context = test_context();
        let server_task = tokio::spawn(async move {
            handle_client(server, context)
                .await
                .expect("server should handle requests");
        });

        let (reader, mut writer) = client.into_split();
        for request in requests {
            writer
                .write_all(request.as_bytes())
                .await
                .expect("write request");
            writer.write_all(b"\n").await.expect("write newline");
        }
        writer.shutdown().await.expect("shutdown writer");

        let mut responses = Vec::new();
        let mut lines = BufReader::new(reader).lines();
        while let Some(line) = lines.next_line().await.expect("read response line") {
            responses.push(serde_json::from_str(&line).expect("valid response json"));
        }

        server_task.await.expect("server task should finish");
        responses
    }

    fn test_context() -> ServerContext {
        let events = Events::new();
        let theme = ThemeController::spawn(events.clone());
        ServerContext {
            airdrop: AirDropController::new(events.clone()),
            airpods: AirPodsController::new(events.clone()),
            night_light: Controller::new(theme.clone(), events.clone()),
            theme,
            hypr: HyprController::new(events.clone(), Arc::default()),
            session: SessionController::new(Default::default(), events.clone()),
            brightness: BrightnessController::new(events.clone()),
            power: Default::default(),
            focus: Default::default(),
            health: SubsystemHealth::new(events.clone()),
            started_at: Instant::now(),
            events,
        }
    }

    /// Redirect every path the snapshot providers touch into a temp dir so
    /// subscribe tests never read or seed the real machine's state.
    fn scoped_test_env(
        temp: &crate::test_support::TempDir,
    ) -> Vec<crate::test_support::ScopedEnvVar> {
        vec![
            crate::test_support::ScopedEnvVar::set(
                "DESKTOPCTL_REPO",
                crate::test_support::repo_root(),
            ),
            crate::test_support::ScopedEnvVar::set("XDG_DATA_HOME", temp.path().join("data")),
            crate::test_support::ScopedEnvVar::set("XDG_CACHE_HOME", temp.path().join("cache")),
            crate::test_support::ScopedEnvVar::set("XDG_CONFIG_HOME", temp.path().join("config")),
        ]
    }

    // Held across awaits on purpose: the guard scopes the env for the whole current-thread test.
    #[allow(clippy::await_holding_lock)]
    #[tokio::test]
    async fn subscribe_confirms_topics_and_forwards_matching_events() {
        let _lock = crate::test_support::env_lock();
        let temp = crate::test_support::TempDir::new("desktopctl-subscribe").expect("temp dir");
        let _env = scoped_test_env(&temp);

        let (client, server) = UnixStream::pair().expect("socket pair");
        let context = test_context();
        let events = context.events.clone();
        let server_task = tokio::spawn(async move {
            let _ = handle_client(server, context).await;
        });

        let (reader, mut writer) = client.into_split();
        writer
            .write_all(b"{\"method\":\"subscribe\",\"params\":{\"topics\":[\"theme\"]}}\n")
            .await
            .expect("write subscribe");

        let mut lines = BufReader::new(reader).lines();
        let reply: serde_json::Value = serde_json::from_str(
            &lines
                .next_line()
                .await
                .expect("read reply")
                .expect("reply line"),
        )
        .expect("valid reply json");
        assert_eq!(
            reply,
            serde_json::json!({ "ok": true, "data": { "subscribed": ["theme"] } })
        );

        // First pushed line is the theme snapshot, then presets snapshot.
        let snapshot: serde_json::Value = serde_json::from_str(
            &lines
                .next_line()
                .await
                .expect("read snapshot")
                .expect("snapshot line"),
        )
        .expect("valid snapshot json");
        assert_eq!(snapshot["event"], serde_json::json!("theme.changed"));
        assert_eq!(snapshot["data"]["changed_keys"], serde_json::json!([]));
        assert!(snapshot["data"]["state"].is_object());

        let presets_snapshot: serde_json::Value = serde_json::from_str(
            &lines
                .next_line()
                .await
                .expect("read presets snapshot")
                .expect("presets snapshot line"),
        )
        .expect("valid presets json");
        assert_eq!(
            presets_snapshot["event"],
            serde_json::json!("theme.presets_changed")
        );
        assert!(presets_snapshot["data"]["presets"].is_array());

        events.publish(
            "night_light.changed",
            serde_json::json!({ "ignored": true }),
        );
        events.publish(
            "theme.changed",
            serde_json::json!({ "changed_keys": ["wallpaper"] }),
        );

        // The night_light event is filtered out; the theme event arrives.
        let event: serde_json::Value = serde_json::from_str(
            &lines
                .next_line()
                .await
                .expect("read event")
                .expect("event line"),
        )
        .expect("valid event json");
        assert_eq!(
            event,
            serde_json::json!({
                "event": "theme.changed",
                "data": { "changed_keys": ["wallpaper"] },
            })
        );

        // A request on a subscribed connection is refused but not fatal.
        writer
            .write_all(b"{\"method\":\"ping\"}\n")
            .await
            .expect("write ping");
        let refusal: serde_json::Value = serde_json::from_str(
            &lines
                .next_line()
                .await
                .expect("read refusal")
                .expect("refusal line"),
        )
        .expect("valid refusal json");
        assert_eq!(refusal["ok"], serde_json::json!(false));

        writer.shutdown().await.expect("shutdown writer");
        server_task.await.expect("server task should finish");
    }
}
