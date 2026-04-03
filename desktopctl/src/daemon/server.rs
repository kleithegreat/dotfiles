use crate::paths;
use serde::Deserialize;
use std::{io, path::Path};
use tokio::{
    fs,
    io::{AsyncBufReadExt, AsyncWriteExt, BufReader},
    net::{UnixListener, UnixStream},
    sync::watch,
};

#[derive(Debug, Deserialize)]
struct Request {
    method: String,
}

pub async fn run(mut shutdown: watch::Receiver<bool>) -> crate::Result<()> {
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
                    tokio::spawn(async move {
                        let _ = handle_client(stream).await;
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
    if fs::metadata(path).await.is_err() {
        return Ok(());
    }

    match UnixStream::connect(path).await {
        Ok(_) => Err(io::Error::new(
            io::ErrorKind::AddrInUse,
            format!("socket already in use: {}", path.display()),
        )),
        Err(_) => fs::remove_file(path).await,
    }
}

async fn handle_client(stream: UnixStream) -> io::Result<()> {
    let (reader, mut writer) = stream.into_split();
    let mut lines = BufReader::new(reader).lines();

    while let Some(line) = lines.next_line().await? {
        if line.trim().is_empty() {
            continue;
        }

        let response = match serde_json::from_str::<Request>(&line) {
            Ok(request) if request.method == "ping" => r#"{"ok":true,"data":{"pong":true}}"#,
            Ok(request) => {
                let error = serde_json::json!({
                    "ok": false,
                    "error": format!("unsupported method: {}", request.method),
                });
                writer.write_all(error.to_string().as_bytes()).await?;
                writer.write_all(b"\n").await?;
                continue;
            }
            Err(error) => {
                let error = serde_json::json!({
                    "ok": false,
                    "error": format!("invalid request: {error}"),
                });
                writer.write_all(error.to_string().as_bytes()).await?;
                writer.write_all(b"\n").await?;
                continue;
            }
        };

        writer.write_all(response.as_bytes()).await?;
        writer.write_all(b"\n").await?;
    }

    Ok(())
}
