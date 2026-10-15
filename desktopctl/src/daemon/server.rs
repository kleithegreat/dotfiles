use crate::{
    daemon::{
        brightness::BrightnessController,
        hypr::HyprController,
        night_light::Controller,
        session::SessionController,
        theme::{ThemeController, ThemeJob},
    },
    ipc::{self, EventEnvelope, methods},
    night_light::NightLightSetParams,
    theme::{ApplyScope, DarkHintOrigin},
};
use serde::Deserialize;
use std::{io, os::unix::fs::FileTypeExt, path::Path, sync::Arc};
use tokio::{
    fs,
    io::{AsyncBufReadExt, AsyncWrite, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::{broadcast, watch},
};

#[derive(Debug, Deserialize)]
struct Request {
    method: String,
    #[serde(default)]
    params: serde_json::Value,
}

#[derive(Debug, Default, Deserialize)]
struct SubscribeParams {
    #[serde(default)]
    topics: Vec<String>,
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
        // A send error only means no subscriber is connected right now.
        let _ = self.sender.send(Arc::new(EventEnvelope {
            event: event.to_owned(),
            data,
        }));
    }

    fn receiver(&self) -> broadcast::Receiver<Arc<EventEnvelope>> {
        self.sender.subscribe()
    }
}

/// Everything a client connection can reach.
#[derive(Clone)]
pub struct ServerContext {
    pub night_light: Controller,
    pub theme: ThemeController,
    pub hypr: HyprController,
    pub session: SessionController,
    pub brightness: BrightnessController,
    pub events: Events,
}

#[derive(Debug, Default, Deserialize)]
struct BrightnessDeviceParams {
    #[serde(default)]
    device: Option<String>,
}

#[derive(Debug, Deserialize)]
struct BrightnessSetParams {
    #[serde(default)]
    device: Option<String>,
    percent: u16,
}

#[derive(Debug, Deserialize)]
struct BrightnessStepParams {
    #[serde(default)]
    device: Option<String>,
    direction: String,
}

#[derive(Debug, Deserialize)]
struct KeyValueParams {
    key: String,
    value: String,
}

#[derive(Debug, Deserialize)]
struct MonitorsPrimaryParams {
    selector: String,
}

#[derive(Debug, Deserialize)]
struct SessionAutomaticParams {
    automatic: bool,
}

#[derive(Debug, Default, Deserialize)]
struct SessionRestoreParams {
    #[serde(default)]
    if_automatic: bool,
}

#[derive(Debug, Deserialize)]
struct MonitorsLayoutParams {
    outputs: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct ThemeSetParams {
    key: String,
    value: serde_json::Value,
}

#[derive(Debug, Deserialize)]
struct ThemeApplyParams {
    scope: String,
    #[serde(default)]
    target: Option<String>,
}

#[derive(Debug, Deserialize)]
struct NamedParams {
    name: String,
}

#[derive(Debug, Deserialize)]
struct PresetSaveParams {
    name: String,
    payload: serde_json::Value,
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
                        // Transient accept failures (e.g. ECONNABORTED, EMFILE)
                        // must not take the whole daemon down.
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

async fn handle_client(stream: UnixStream, context: ServerContext) -> io::Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();

    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }

        let request = match serde_json::from_str::<Request>(&line) {
            Ok(request) => request,
            Err(error) => {
                write_error(&mut writer, format!("invalid request: {error}")).await?;
                continue;
            }
        };

        if request.method == methods::SUBSCRIBE {
            let params = match parse_params_or_default::<SubscribeParams>(
                request.params,
                methods::SUBSCRIBE,
            ) {
                Ok(params) => params,
                Err(message) => {
                    write_error(&mut writer, message).await?;
                    continue;
                }
            };
            let topics = resolve_topics(params.topics);
            // Subscribe before confirming so an event published right
            // after the client sees the reply cannot be lost.
            let receiver = context.events.receiver();
            write_ok(&mut writer, serde_json::json!({ "subscribed": topics })).await?;
            return run_subscription(&mut writer, &mut lines, topics, context, receiver).await;
        }

        match respond(&request.method, request.params, &context).await {
            Ok(data) => write_ok(&mut writer, data).await?,
            Err(message) => write_error(&mut writer, message).await?,
        }
    }

    Ok(())
}

async fn respond(
    method: &str,
    params: serde_json::Value,
    context: &ServerContext,
) -> Result<serde_json::Value, String> {
    match method {
        methods::PING => Ok(serde_json::json!({ "pong": true })),
        methods::NIGHT_LIGHT_STATUS => {
            let controller = context.night_light.clone();
            blocking(move || controller.status()).await
        }
        methods::NIGHT_LIGHT_SET => {
            let params: NightLightSetParams = parse_params(params, method)?;
            let controller = context.night_light.clone();
            blocking(move || controller.set_mode(params.mode, params.temperature)).await
        }
        methods::NIGHT_LIGHT_TOGGLE => {
            let controller = context.night_light.clone();
            blocking(move || controller.toggle()).await
        }
        methods::THEME_STATUS => {
            blocking(|| {
                crate::theme::resolve::load_state().map(|state| crate::theme::state_json(&state))
            })
            .await
        }
        methods::THEME_SET => {
            let params: ThemeSetParams = parse_params(params, method)?;
            let job = ThemeJob::Set {
                key: params.key,
                value: params.value,
                // User-initiated; the schedule bypasses this method.
                origin: DarkHintOrigin::Manual,
            };
            to_value(context.theme.request(job).await)
        }
        methods::THEME_APPLY => {
            let params: ThemeApplyParams = parse_params(params, method)?;
            let scope = ApplyScope::parse(&params.scope, params.target)
                .map_err(|error| error.to_string())?;
            to_value(context.theme.request(ThemeJob::Apply { scope }).await)
        }
        methods::THEME_PRESET_APPLY => {
            let params: NamedParams = parse_params(params, method)?;
            to_value(
                context
                    .theme
                    .request(ThemeJob::PresetApply { name: params.name })
                    .await,
            )
        }
        methods::THEME_PRESET_SAVE => {
            let params: PresetSaveParams = parse_params(params, method)?;
            let job = ThemeJob::PresetSave {
                name: params.name,
                payload: params.payload,
            };
            to_value(context.theme.request(job).await)
        }
        methods::THEME_PRESET_DELETE => {
            let params: NamedParams = parse_params(params, method)?;
            to_value(
                context
                    .theme
                    .request(ThemeJob::PresetDelete { name: params.name })
                    .await,
            )
        }
        methods::HYPR_INPUT_STATUS => {
            let hypr = context.hypr.clone();
            blocking(move || hypr.input_status()).await
        }
        methods::HYPR_INPUT_SET => {
            let params: KeyValueParams = parse_params(params, method)?;
            let hypr = context.hypr.clone();
            blocking(move || hypr.input_set(&params.key, &params.value)).await
        }
        methods::HYPR_MONITORS_STATUS => {
            let hypr = context.hypr.clone();
            blocking(move || hypr.monitors_status()).await
        }
        methods::HYPR_MONITORS_PRIMARY => {
            let params: MonitorsPrimaryParams = parse_params(params, method)?;
            let hypr = context.hypr.clone();
            blocking(move || hypr.monitors_primary(&params.selector)).await
        }
        methods::HYPR_MONITORS_LAYOUT => {
            let params: MonitorsLayoutParams = parse_params(params, method)?;
            let hypr = context.hypr.clone();
            blocking(move || hypr.monitors_layout(&params.outputs)).await
        }
        methods::SESSION_STATUS => to_value(context.session.status()),
        methods::SESSION_AUTOMATIC => {
            let params: SessionAutomaticParams = parse_params(params, method)?;
            to_value(context.session.set_automatic(params.automatic))
        }
        methods::SESSION_RESTORE => {
            let params: SessionRestoreParams = parse_params_or_default(params, method)?;
            let session = context.session.clone();
            blocking(move || session.restore(params.if_automatic)).await
        }
        methods::BRIGHTNESS_STATUS => {
            let brightness = context.brightness.clone();
            blocking(move || brightness.status()).await
        }
        methods::BRIGHTNESS_SET => {
            let params: BrightnessSetParams = parse_params(params, method)?;
            let brightness = context.brightness.clone();
            blocking(move || brightness.set(params.device.as_deref(), params.percent)).await
        }
        methods::BRIGHTNESS_STEP => {
            let params: BrightnessStepParams = parse_params(params, method)?;
            let direction = match params.direction.as_str() {
                "up" => 1.0,
                "down" => -1.0,
                other => return Err(format!("invalid step direction '{other}'")),
            };
            let brightness = context.brightness.clone();
            blocking(move || brightness.step(params.device.as_deref(), direction)).await
        }
        methods::BRIGHTNESS_DIM => {
            let params: BrightnessDeviceParams = parse_params_or_default(params, method)?;
            let brightness = context.brightness.clone();
            blocking(move || brightness.dim(params.device.as_deref())).await
        }
        methods::BRIGHTNESS_RESTORE => {
            let params: BrightnessDeviceParams = parse_params_or_default(params, method)?;
            let brightness = context.brightness.clone();
            blocking(move || brightness.restore(params.device.as_deref())).await
        }
        _ => Err(format!("unsupported method: {method}")),
    }
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

/// Like [`parse_params`], but a missing/null params object means defaults.
fn parse_params_or_default<T>(params: serde_json::Value, method: &str) -> Result<T, String>
where
    T: serde::de::DeserializeOwned + Default,
{
    if params.is_null() {
        return Ok(T::default());
    }
    parse_params(params, method)
}

fn parse_params<T: serde::de::DeserializeOwned>(
    params: serde_json::Value,
    method: &str,
) -> Result<T, String> {
    serde_json::from_value(params).map_err(|error| format!("invalid params for {method}: {error}"))
}

fn resolve_topics(requested: Vec<String>) -> Vec<String> {
    if requested.is_empty() {
        return ipc::TOPICS
            .iter()
            .map(|topic| (*topic).to_owned())
            .collect();
    }

    requested
        .into_iter()
        .filter(|topic| ipc::TOPICS.contains(&topic.as_str()))
        .collect()
}

/// After a `subscribe` reply the connection becomes push-only: snapshots for
/// each topic first, then matching events as controllers publish them. The
/// read half is drained only to notice EOF; further requests are refused.
async fn run_subscription<W, R>(
    writer: &mut W,
    lines: &mut tokio::io::Lines<BufReader<R>>,
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
            line = lines.next_line() => match line? {
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
                blocking(|| {
                    crate::theme::resolve::load_state().map(|state| {
                        serde_json::json!({
                            "state": crate::theme::state_json(&state),
                            "changed_keys": [],
                        })
                    })
                })
                .await
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

    // The DDC half enumerates I2C buses (~1s); it follows the cheap topics so
    // nothing waits on it. Subscribers merge snapshot events by device.
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

    #[test]
    fn request_deserialization_defaults_missing_params_to_null() {
        let request: Request =
            serde_json::from_str(r#"{"method":"ping"}"#).expect("request should deserialize");

        assert_eq!(request.method, "ping");
        assert_eq!(request.params, serde_json::Value::Null);
    }

    #[tokio::test]
    async fn handle_client_replies_to_ping_and_skips_blank_lines() {
        let responses = send_requests(&["", r#"{"method":"ping"}"#]).await;

        assert_eq!(responses.len(), 1);
        assert_eq!(
            responses[0],
            serde_json::json!({
                "ok": true,
                "data": {
                    "pong": true,
                },
            })
        );
    }

    #[tokio::test]
    async fn handle_client_reports_invalid_requests_and_invalid_params() {
        let responses = send_requests(&[
            "{not valid json",
            r#"{"method":"night_light.set","params":{"mode":"invalid"}}"#,
        ])
        .await;

        assert_eq!(responses.len(), 2);
        assert_eq!(responses[0]["ok"], serde_json::json!(false));
        assert!(
            responses[0]["error"]
                .as_str()
                .expect("error string")
                .starts_with("invalid request:")
        );
        assert_eq!(responses[1]["ok"], serde_json::json!(false));
        assert!(
            responses[1]["error"]
                .as_str()
                .expect("error string")
                .starts_with("invalid params for night_light.set:")
        );
    }

    #[tokio::test]
    async fn handle_client_reports_unsupported_methods() {
        let responses = send_requests(&[r#"{"method":"unknown.method"}"#]).await;

        assert_eq!(responses.len(), 1);
        assert_eq!(
            responses[0],
            serde_json::json!({
                "ok": false,
                "error": "unsupported method: unknown.method",
            })
        );
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
        ServerContext {
            night_light: Controller::new(),
            theme: ThemeController::spawn(events.clone()),
            hypr: HyprController::new(events.clone()),
            session: SessionController::new(Default::default(), events.clone()),
            brightness: BrightnessController::new(events.clone()),
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

    // The env guard is deliberately held across awaits: this is a
    // current-thread test runtime and the guard scopes the process-global
    // env for the whole scenario.
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
            .write_all(
                b"{\"method\":\"subscribe\",\"params\":{\"topics\":[\"theme\",\"bogus\"]}}\n",
            )
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

        // First pushed line is the theme snapshot (freshly seeded defaults).
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

    // Unit-level on purpose: a full subscribe with every topic would run the
    // brightness snapshot's real DDC enumeration.
    #[test]
    fn resolve_topics_defaults_to_every_topic_and_drops_unknown_ones() {
        assert_eq!(
            resolve_topics(Vec::new()),
            vec![
                "theme",
                "night_light",
                "brightness",
                "hypr_input",
                "hypr_monitors",
                "session"
            ]
        );
        assert_eq!(
            resolve_topics(vec!["night_light".to_owned(), "bogus".to_owned()]),
            vec!["night_light"]
        );
    }
}
