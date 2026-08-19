use crate::{
    daemon::{
        brightness::BrightnessController,
        hypr::HyprController,
        night_light::Controller,
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

#[derive(Debug, Deserialize)]
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

/// Everything a client connection can reach. Grows a field per controller as
/// state ownership moves into the daemon.
#[derive(Clone)]
pub struct ServerContext {
    pub night_light: Controller,
    pub theme: ThemeController,
    pub hypr: HyprController,
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
struct PayloadParams {
    payload: serde_json::Value,
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

        match request.method.as_str() {
            methods::PING => {
                write_ok(&mut writer, serde_json::json!({ "pong": true })).await?;
            }
            methods::SUBSCRIBE => {
                let params = if request.params.is_null() {
                    Ok(SubscribeParams { topics: Vec::new() })
                } else {
                    serde_json::from_value::<SubscribeParams>(request.params)
                };
                let params = match params {
                    Ok(params) => params,
                    Err(error) => {
                        write_error(
                            &mut writer,
                            format!("invalid params for {}: {error}", methods::SUBSCRIBE),
                        )
                        .await?;
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
            methods::NIGHT_LIGHT_STATUS => {
                let controller = context.night_light.clone();
                match tokio::task::spawn_blocking(move || controller.status()).await {
                    Ok(Ok(status)) => write_ok(&mut writer, status).await?,
                    Ok(Err(error)) => write_error(&mut writer, error.to_string()).await?,
                    Err(error) => write_error(&mut writer, error.to_string()).await?,
                }
            }
            methods::NIGHT_LIGHT_SET => {
                let params = match serde_json::from_value::<NightLightSetParams>(request.params) {
                    Ok(params) => params,
                    Err(error) => {
                        write_error(
                            &mut writer,
                            format!("invalid params for {}: {error}", methods::NIGHT_LIGHT_SET),
                        )
                        .await?;
                        continue;
                    }
                };

                let controller = context.night_light.clone();
                match tokio::task::spawn_blocking(move || {
                    controller.set_mode(params.mode, params.temperature)
                })
                .await
                {
                    Ok(Ok(status)) => write_ok(&mut writer, status).await?,
                    Ok(Err(error)) => write_error(&mut writer, error.to_string()).await?,
                    Err(error) => write_error(&mut writer, error.to_string()).await?,
                }
            }
            methods::NIGHT_LIGHT_TOGGLE => {
                let controller = context.night_light.clone();
                match tokio::task::spawn_blocking(move || controller.toggle()).await {
                    Ok(Ok(status)) => write_ok(&mut writer, status).await?,
                    Ok(Err(error)) => write_error(&mut writer, error.to_string()).await?,
                    Err(error) => write_error(&mut writer, error.to_string()).await?,
                }
            }
            methods::THEME_STATUS => {
                let result = tokio::task::spawn_blocking(|| {
                    crate::theme::resolve::load_state().map(|state| crate::theme::state_json(&state))
                })
                .await;
                match result {
                    Ok(Ok(state)) => write_ok(&mut writer, state).await?,
                    Ok(Err(error)) => write_error(&mut writer, error.to_string()).await?,
                    Err(error) => write_error(&mut writer, error.to_string()).await?,
                }
            }
            methods::THEME_SET => {
                match parse_params::<ThemeSetParams>(request.params, methods::THEME_SET) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let job = ThemeJob::Set {
                            key: params.key,
                            value: params.value,
                            // Every socket write is user-initiated; the
                            // schedule mutates through the controller
                            // directly, not through this method.
                            origin: DarkHintOrigin::Manual,
                        };
                        write_result(&mut writer, context.theme.request(job).await).await?;
                    }
                }
            }
            methods::THEME_APPLY => {
                match parse_params::<ThemeApplyParams>(request.params, methods::THEME_APPLY) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => match ApplyScope::parse(&params.scope, params.target) {
                        Err(error) => write_error(&mut writer, error.to_string()).await?,
                        Ok(scope) => {
                            let job = ThemeJob::Apply { scope };
                            write_result(&mut writer, context.theme.request(job).await).await?;
                        }
                    },
                }
            }
            methods::THEME_PRESET_APPLY => {
                match parse_params::<NamedParams>(request.params, methods::THEME_PRESET_APPLY) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let job = ThemeJob::PresetApply { name: params.name };
                        write_result(&mut writer, context.theme.request(job).await).await?;
                    }
                }
            }
            methods::THEME_PRESET_SAVE => {
                match parse_params::<PresetSaveParams>(request.params, methods::THEME_PRESET_SAVE) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let job = ThemeJob::PresetSave {
                            name: params.name,
                            payload: params.payload,
                        };
                        write_result(&mut writer, context.theme.request(job).await).await?;
                    }
                }
            }
            methods::THEME_PRESET_DELETE => {
                match parse_params::<NamedParams>(request.params, methods::THEME_PRESET_DELETE) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let job = ThemeJob::PresetDelete { name: params.name };
                        write_result(&mut writer, context.theme.request(job).await).await?;
                    }
                }
            }
            methods::HYPR_INPUT_STATUS => {
                let hypr = context.hypr.clone();
                let result = tokio::task::spawn_blocking(move || hypr.input_status()).await;
                write_join_result(&mut writer, result).await?;
            }
            methods::HYPR_INPUT_SET => {
                match parse_params::<KeyValueParams>(request.params, methods::HYPR_INPUT_SET) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let hypr = context.hypr.clone();
                        let result = tokio::task::spawn_blocking(move || {
                            hypr.input_set(&params.key, &params.value)
                        })
                        .await;
                        write_join_result(&mut writer, result).await?;
                    }
                }
            }
            methods::HYPR_ANIMATIONS_SAVE => {
                match parse_params::<PayloadParams>(request.params, methods::HYPR_ANIMATIONS_SAVE) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let hypr = context.hypr.clone();
                        let result = tokio::task::spawn_blocking(move || {
                            hypr.animations_save(&params.payload)
                        })
                        .await;
                        write_join_result(&mut writer, result).await?;
                    }
                }
            }
            methods::HYPR_ANIMATIONS_CLEAR => {
                let hypr = context.hypr.clone();
                let result = tokio::task::spawn_blocking(move || hypr.animations_clear()).await;
                write_join_result(&mut writer, result).await?;
            }
            methods::BRIGHTNESS_STATUS => {
                let brightness = context.brightness.clone();
                let result = tokio::task::spawn_blocking(move || brightness.status()).await;
                write_join_result(&mut writer, result).await?;
            }
            methods::BRIGHTNESS_SET => {
                match parse_params::<BrightnessSetParams>(request.params, methods::BRIGHTNESS_SET) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let brightness = context.brightness.clone();
                        let result = tokio::task::spawn_blocking(move || {
                            brightness.set(params.device.as_deref(), params.percent)
                        })
                        .await;
                        write_join_result(&mut writer, result).await?;
                    }
                }
            }
            methods::BRIGHTNESS_STEP => {
                match parse_params::<BrightnessStepParams>(request.params, methods::BRIGHTNESS_STEP)
                {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let direction = match params.direction.as_str() {
                            "up" => 1.0,
                            "down" => -1.0,
                            other => {
                                write_error(
                                    &mut writer,
                                    format!("invalid step direction '{other}'"),
                                )
                                .await?;
                                continue;
                            }
                        };
                        let brightness = context.brightness.clone();
                        let result = tokio::task::spawn_blocking(move || {
                            brightness.step(params.device.as_deref(), direction)
                        })
                        .await;
                        write_join_result(&mut writer, result).await?;
                    }
                }
            }
            methods::BRIGHTNESS_DIM => {
                match parse_params_or_default::<BrightnessDeviceParams>(
                    request.params,
                    methods::BRIGHTNESS_DIM,
                ) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let brightness = context.brightness.clone();
                        let result = tokio::task::spawn_blocking(move || {
                            brightness.dim(params.device.as_deref())
                        })
                        .await;
                        write_join_result(&mut writer, result).await?;
                    }
                }
            }
            methods::BRIGHTNESS_RESTORE => {
                match parse_params_or_default::<BrightnessDeviceParams>(
                    request.params,
                    methods::BRIGHTNESS_RESTORE,
                ) {
                    Err(message) => write_error(&mut writer, message).await?,
                    Ok(params) => {
                        let brightness = context.brightness.clone();
                        let result = tokio::task::spawn_blocking(move || {
                            brightness.restore(params.device.as_deref())
                        })
                        .await;
                        write_join_result(&mut writer, result).await?;
                    }
                }
            }
            _ => {
                write_error(
                    &mut writer,
                    format!("unsupported method: {}", request.method),
                )
                .await?;
            }
        }
    }

    Ok(())
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

async fn write_join_result<W: AsyncWrite + Unpin>(
    writer: &mut W,
    result: Result<crate::Result<serde_json::Value>, tokio::task::JoinError>,
) -> io::Result<()> {
    match result {
        Ok(result) => write_result(writer, result).await,
        Err(error) => write_error(writer, error.to_string()).await,
    }
}

fn parse_params<T: serde::de::DeserializeOwned>(
    params: serde_json::Value,
    method: &str,
) -> Result<T, String> {
    serde_json::from_value(params).map_err(|error| format!("invalid params for {method}: {error}"))
}

async fn write_result<W: AsyncWrite + Unpin>(
    writer: &mut W,
    result: crate::Result<serde_json::Value>,
) -> io::Result<()> {
    match result {
        Ok(data) => write_ok(writer, data).await,
        Err(error) => write_error(writer, error.to_string()).await,
    }
}

fn resolve_topics(requested: Vec<String>) -> Vec<String> {
    if requested.is_empty() {
        return ipc::TOPICS.iter().map(|topic| (*topic).to_owned()).collect();
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
    // Brightness last: its snapshot enumerates DDC buses (~1s) and must not
    // delay the cheap ones.
    let mut ordered: Vec<&String> = topics.iter().filter(|t| *t != "brightness").collect();
    ordered.extend(topics.iter().filter(|t| *t == "brightness"));

    for topic in ordered {
        match topic.as_str() {
            "night_light" => {
                let controller = context.night_light.clone();
                if let Ok(Ok(status)) =
                    tokio::task::spawn_blocking(move || controller.status()).await
                {
                    let event = EventEnvelope {
                        event: "night_light.changed".to_owned(),
                        data: serde_json::to_value(status).unwrap_or(serde_json::Value::Null),
                    };
                    write_event(writer, &event).await?;
                }
            }
            "theme" => {
                if let Ok(Ok(state)) = tokio::task::spawn_blocking(|| {
                    crate::theme::resolve::load_state().map(|state| crate::theme::state_json(&state))
                })
                .await
                {
                    let event = EventEnvelope {
                        event: "theme.changed".to_owned(),
                        data: serde_json::json!({ "state": state, "changed_keys": [] }),
                    };
                    write_event(writer, &event).await?;
                }
            }
            "hypr_input" => {
                let hypr = context.hypr.clone();
                if let Ok(Ok(state)) =
                    tokio::task::spawn_blocking(move || hypr.input_status()).await
                {
                    let event = EventEnvelope {
                        event: "hypr_input.changed".to_owned(),
                        data: state,
                    };
                    write_event(writer, &event).await?;
                }
            }
            "brightness" => {
                let brightness = context.brightness.clone();
                if let Ok(Ok(devices)) =
                    tokio::task::spawn_blocking(move || brightness.status()).await
                {
                    let event = EventEnvelope {
                        event: "brightness.changed".to_owned(),
                        data: serde_json::json!({
                            "devices": devices.get("devices").cloned()
                                .unwrap_or(serde_json::Value::Array(Vec::new())),
                            "osd": false,
                        }),
                    };
                    write_event(writer, &event).await?;
                }
            }
            _ => {}
        }
    }

    Ok(())
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
            brightness: BrightnessController::new(events.clone()),
            events,
        }
    }

    /// Redirect every path the snapshot providers touch into a temp dir so
    /// subscribe tests never read or seed the real machine's state.
    fn scoped_test_env(
        temp: &crate::test_support::TempDir,
    ) -> Vec<crate::test_support::ScopedEnvVar> {
        let repo_root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .parent()
            .expect("crate lives inside the repo")
            .to_path_buf();
        vec![
            crate::test_support::ScopedEnvVar::set("DESKTOPCTL_REPO", &repo_root),
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
            .write_all(b"{\"method\":\"subscribe\",\"params\":{\"topics\":[\"theme\",\"bogus\"]}}\n")
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

        events.publish("night_light.changed", serde_json::json!({ "ignored": true }));
        events.publish("theme.changed", serde_json::json!({ "changed_keys": ["wallpaper"] }));

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
            vec!["theme", "night_light", "brightness", "hypr_input"]
        );
        assert_eq!(
            resolve_topics(vec!["night_light".to_owned(), "bogus".to_owned()]),
            vec!["night_light"]
        );
    }
}
