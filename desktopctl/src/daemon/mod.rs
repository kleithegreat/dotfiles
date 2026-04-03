pub mod focus;
pub mod night_light;
pub mod server;
pub mod solar;

use std::{
    io,
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
};
use tokio::{
    runtime::Builder,
    signal::unix::{SignalKind, signal},
    sync::watch,
    task::JoinSet,
};

pub fn run() -> crate::Result<()> {
    Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(run_async())
}

async fn run_async() -> crate::Result<()> {
    let shutdown = Arc::new(AtomicBool::new(false));
    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let night_light = night_light::Controller::new();
    let mut tasks = JoinSet::new();

    {
        let shutdown = Arc::clone(&shutdown);
        tasks.spawn_blocking(move || ("focus tracker", focus::run(shutdown)));
    }
    tasks.spawn({
        let night_light = night_light.clone();
        let shutdown_rx = shutdown_rx.clone();
        async move {
            (
                "solar scheduler",
                solar::run(night_light, shutdown_rx).await,
            )
        }
    });
    tasks.spawn({
        let night_light = night_light.clone();
        let shutdown_rx = shutdown_rx.clone();
        async move { ("socket server", server::run(night_light, shutdown_rx).await) }
    });

    let mut sigterm = signal(SignalKind::terminate())?;
    let mut sigint = signal(SignalKind::interrupt())?;
    let mut task_failure: Option<Box<dyn std::error::Error + Send + Sync>> = None;

    tokio::select! {
        _ = sigterm.recv() => {}
        _ = sigint.recv() => {}
        task = tasks.join_next() => {
            task_failure = Some(handle_task_exit(task)?);
        }
    }

    shutdown.store(true, Ordering::SeqCst);
    let _ = shutdown_tx.send(true);

    while let Some(task) = tasks.join_next().await {
        match task {
            Ok((name, Ok(()))) => {
                if task_failure.is_none() {
                    task_failure =
                        Some(io::Error::other(format!("{name} exited unexpectedly")).into());
                }
            }
            Ok((_, Err(error))) => {
                if task_failure.is_none() {
                    task_failure = Some(error);
                }
            }
            Err(error) => {
                if task_failure.is_none() {
                    task_failure =
                        Some(io::Error::other(format!("daemon task join failed: {error}")).into());
                }
            }
        }
    }

    if let Some(error) = task_failure {
        return Err(error);
    }

    Ok(())
}

fn handle_task_exit(
    task: Option<Result<(&'static str, crate::Result<()>), tokio::task::JoinError>>,
) -> crate::Result<Box<dyn std::error::Error + Send + Sync>> {
    let Some(task) = task else {
        return Err(io::Error::other("daemon exited before starting any tasks").into());
    };

    let (name, result) =
        task.map_err(|error| io::Error::other(format!("daemon task join failed: {error}")))?;
    match result {
        Ok(()) => Ok(io::Error::other(format!("{name} exited unexpectedly")).into()),
        Err(error) => Ok(error),
    }
}
