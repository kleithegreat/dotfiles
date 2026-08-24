pub mod brightness;
pub mod focus;
pub mod hypr;
pub mod monitors;
pub mod night_light;
pub mod server;
pub mod solar;
pub mod theme;

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
    let events = server::Events::new();
    let theme = theme::ThemeController::spawn(events.clone());
    let night_light = night_light::Controller::with_hooks(theme.clone(), events.clone());
    let hypr = hypr::HyprController::new(events.clone());

    // Auxiliary subsystems get their own failure domain. A focus tracker or
    // solar scheduler that dies must not take the socket server with it: the
    // socket is what every write subcommand and the shell depend on, and
    // those subsystems have nothing to do with each other.
    let mut auxiliary = JoinSet::new();
    {
        let shutdown = Arc::clone(&shutdown);
        auxiliary.spawn_blocking(move || ("focus tracker", focus::run(shutdown)));
    }
    {
        let shutdown = Arc::clone(&shutdown);
        let hypr = hypr.clone();
        let theme = theme.clone();
        auxiliary.spawn_blocking(move || ("monitor watcher", monitors::run(shutdown, hypr, theme)));
    }
    auxiliary.spawn({
        let night_light = night_light.clone();
        let theme = theme.clone();
        let shutdown_rx = shutdown_rx.clone();
        async move {
            (
                "solar scheduler",
                solar::run(night_light, theme, shutdown_rx).await,
            )
        }
    });

    let supervisor = tokio::spawn(async move {
        while let Some(task) = auxiliary.join_next().await {
            report_auxiliary_exit(task);
        }
    });

    let mut server = tokio::spawn({
        let context = server::ServerContext {
            night_light: night_light.clone(),
            theme: theme.clone(),
            hypr: hypr.clone(),
            brightness: brightness::BrightnessController::new(events.clone()),
            events: events.clone(),
        };
        let shutdown_rx = shutdown_rx.clone();
        async move { server::run(context, shutdown_rx).await }
    });

    let mut sigterm = signal(SignalKind::terminate())?;
    let mut sigint = signal(SignalKind::interrupt())?;
    let mut server_failure = None;

    tokio::select! {
        _ = sigterm.recv() => {}
        _ = sigint.recv() => {}
        result = &mut server => {
            server_failure = Some(server_exit_error(result));
        }
    }

    shutdown.store(true, Ordering::SeqCst);
    let _ = shutdown_tx.send(true);
    let _ = supervisor.await;

    match server_failure {
        Some(error) => Err(error),
        None => match server.await {
            Ok(result) => result,
            Err(error) => {
                Err(io::Error::other(format!("socket server task join failed: {error}")).into())
            }
        },
    }
}

/// The server stopping on its own is always fatal — nothing else keeps the
/// daemon useful — so the process exits and the unit's `Restart=on-failure`
/// brings it back.
fn server_exit_error(
    result: Result<crate::Result<()>, tokio::task::JoinError>,
) -> Box<dyn std::error::Error + Send + Sync> {
    match result {
        Ok(Ok(())) => io::Error::other("socket server exited unexpectedly").into(),
        Ok(Err(error)) => error,
        Err(error) => io::Error::other(format!("socket server task join failed: {error}")).into(),
    }
}

/// Auxiliary failures are reported and survived. Under the user unit this
/// reaches the journal, which is the only place it would otherwise be lost.
fn report_auxiliary_exit(task: Result<(&'static str, crate::Result<()>), tokio::task::JoinError>) {
    match task {
        Ok((name, Ok(()))) => eprintln!("desktopctl: {name} exited"),
        Ok((name, Err(error))) => eprintln!("desktopctl: {name} failed: {error}"),
        Err(error) => eprintln!("desktopctl: auxiliary task join failed: {error}"),
    }
}
