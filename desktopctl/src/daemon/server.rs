use crate::{
    daemon::night_light::Controller,
    night_light::{
        METHOD_NIGHT_LIGHT_SET, METHOD_NIGHT_LIGHT_STATUS, METHOD_NIGHT_LIGHT_TOGGLE,
        NightLightSetParams,
    },
    paths,
};
use serde::Deserialize;
use std::{io, path::Path};
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
            METHOD_NIGHT_LIGHT_STATUS => match controller.status() {
                Ok(status) => write_ok(&mut writer, status).await?,
                Err(error) => write_error(&mut writer, error.to_string()).await?,
            },
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

                match controller.set_mode(params.mode, params.temperature) {
                    Ok(status) => write_ok(&mut writer, status).await?,
                    Err(error) => write_error(&mut writer, error.to_string()).await?,
                }
            }
            METHOD_NIGHT_LIGHT_TOGGLE => match controller.toggle() {
                Ok(status) => write_ok(&mut writer, status).await?,
                Err(error) => write_error(&mut writer, error.to_string()).await?,
            },
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
