use crate::{
    daemon::night_light::Controller,
    night_light::{
        METHOD_NIGHT_LIGHT_SET, METHOD_NIGHT_LIGHT_STATUS, METHOD_NIGHT_LIGHT_TOGGLE,
        NightLightSetParams,
    },
    paths,
};
use serde::Deserialize;
use std::{io, os::unix::fs::FileTypeExt, path::Path};
use tokio::{
    fs,
    io::{AsyncBufReadExt, AsyncWrite, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::watch,
};

#[derive(Debug, Deserialize)]
struct Request {
    method: String,
    #[serde(default)]
    params: serde_json::Value,
}

pub async fn run(controller: Controller, mut shutdown: watch::Receiver<bool>) -> crate::Result<()> {
    let socket_path = paths::xdg_runtime_dir()?.join("desktopctl.sock");
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
                    let (stream, _) = accepted?;
                    let controller = controller.clone();
                    tokio::spawn(async move {
                        let _ = handle_client(stream, controller).await;
                    });
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

async fn handle_client(stream: UnixStream, controller: Controller) -> io::Result<()> {
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
            "ping" => {
                write_ok(&mut writer, serde_json::json!({ "pong": true })).await?;
            }
            METHOD_NIGHT_LIGHT_STATUS => {
                let controller = controller.clone();
                match tokio::task::spawn_blocking(move || controller.status()).await {
                    Ok(Ok(status)) => write_ok(&mut writer, status).await?,
                    Ok(Err(error)) => write_error(&mut writer, error.to_string()).await?,
                    Err(error) => write_error(&mut writer, error.to_string()).await?,
                }
            }
            METHOD_NIGHT_LIGHT_SET => {
                let params = match serde_json::from_value::<NightLightSetParams>(request.params) {
                    Ok(params) => params,
                    Err(error) => {
                        write_error(
                            &mut writer,
                            format!("invalid params for {METHOD_NIGHT_LIGHT_SET}: {error}"),
                        )
                        .await?;
                        continue;
                    }
                };

                let controller = controller.clone();
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
            METHOD_NIGHT_LIGHT_TOGGLE => {
                let controller = controller.clone();
                match tokio::task::spawn_blocking(move || controller.toggle()).await {
                    Ok(Ok(status)) => write_ok(&mut writer, status).await?,
                    Ok(Err(error)) => write_error(&mut writer, error.to_string()).await?,
                    Err(error) => write_error(&mut writer, error.to_string()).await?,
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
        let controller = Controller::new();
        let server_task = tokio::spawn(async move {
            handle_client(server, controller)
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
}
