pub mod airdrop;
pub mod airpods;
pub mod brightness;
pub mod focus;
pub mod hypr;
pub mod hypr_events;
pub mod monitors;
pub mod night_light;
pub mod power;
pub mod server;
pub mod session;
pub mod solar;
pub mod theme;

use serde::Serialize;
use std::{
    collections::BTreeMap,
    io,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::Instant,
};
use tokio::{
    runtime::Builder,
    signal::unix::{SignalKind, signal},
    sync::watch,
    task::JoinSet,
};

#[derive(Debug, Clone, Serialize)]
pub struct SubsystemState {
    pub state: &'static str,
    pub last_error: Option<String>,
    pub restarts: u64,
    pub updated_at: i64,
}

#[derive(Clone)]
pub struct SubsystemHealth {
    inner: Arc<Mutex<BTreeMap<&'static str, SubsystemState>>>,
    events: server::Events,
}

impl SubsystemHealth {
    pub fn new(events: server::Events) -> Self {
        Self {
            inner: Arc::new(Mutex::new(BTreeMap::new())),
            events,
        }
    }

    pub fn set_running(&self, name: &'static str) {
        self.update(name, |entry| {
            let recovered = entry.as_ref().is_some_and(|prev| prev.state == "degraded");
            let restarts =
                entry.as_ref().map_or(0, |prev| prev.restarts) + if recovered { 1 } else { 0 };
            SubsystemState {
                state: "running",
                last_error: None,
                restarts,
                updated_at: chrono::Utc::now().timestamp(),
            }
        });
    }

    pub fn set_degraded(&self, name: &'static str, error: impl Into<String>) {
        let error = error.into();
        self.update(name, |entry| SubsystemState {
            state: "degraded",
            last_error: Some(error),
            restarts: entry.as_ref().map_or(0, |prev| prev.restarts),
            updated_at: chrono::Utc::now().timestamp(),
        });
    }

    pub fn set_stopped(&self, name: &'static str) {
        self.update(name, |entry| {
            let restarts = entry.as_ref().map_or(0, |prev| prev.restarts);
            let last_error = entry.and_then(|prev| prev.last_error);
            SubsystemState {
                state: "stopped",
                last_error,
                restarts,
                updated_at: chrono::Utc::now().timestamp(),
            }
        });
    }

    pub fn snapshot(&self) -> BTreeMap<&'static str, SubsystemState> {
        self.inner
            .lock()
            .map(|guard| guard.clone())
            .unwrap_or_default()
    }

    fn update(
        &self,
        name: &'static str,
        build: impl FnOnce(Option<SubsystemState>) -> SubsystemState,
    ) {
        let snapshot = {
            let Ok(mut guard) = self.inner.lock() else {
                return;
            };
            let prev = guard.get(name).cloned();
            let next = build(prev.clone());
            let changed = prev
                .as_ref()
                .is_none_or(|p| p.state != next.state || p.last_error != next.last_error);
            guard.insert(name, next);
            if !changed {
                return;
            }
            guard.clone()
        };
        if let Ok(value) = serde_json::to_value(snapshot) {
            self.events
                .publish("daemon.changed", serde_json::json!({ "subsystems": value }));
        }
    }
}

pub fn run() -> crate::Result<()> {
    // owly-airdrop reports why a phone's connection ended only through tracing.
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "warn,desktopctl=info,owly_airdrop=debug".into()),
        )
        .with_ansi(false)
        .without_time()
        .with_writer(std::io::stderr)
        .init();
    Builder::new_multi_thread()
        .enable_all()
        .build()?
        .block_on(run_async())
}

async fn run_async() -> crate::Result<()> {
    let shutdown = Arc::new(AtomicBool::new(false));
    let (shutdown_tx, shutdown_rx) = watch::channel(false);
    let events = server::Events::new();
    let health = SubsystemHealth::new(events.clone());
    let hypr_events = hypr_events::HyprEvents::new();
    let panel_hz: monitors::SharedPanelHz = Arc::new(Mutex::new(None));
    let resolver = Arc::new(focus::DesktopResolver::load());
    let system_bus = match zbus::Connection::system().await {
        Ok(connection) => Some(connection),
        Err(error) => {
            tracing::warn!(error = %error, "system D-Bus unavailable; bus-backed services degraded");
            None
        }
    };

    let theme = theme::ThemeController::spawn(events.clone());
    let night_light = night_light::Controller::new(theme.clone(), events.clone());
    let hypr = hypr::HyprController::new(events.clone(), Arc::clone(&panel_hz));
    crate::session::unpark(&crate::session::whole_app_classes());
    let session = session::SessionController::new(
        crate::session::load_state().unwrap_or_else(|error| {
            tracing::warn!(error = %error, "session state unreadable, starting empty");
            Default::default()
        }),
        events.clone(),
    );

    let mut auxiliary = JoinSet::new();
    auxiliary.spawn({
        let hypr_events = hypr_events.clone();
        let shutdown_rx = shutdown_rx.clone();
        let health = health.clone();
        async move {
            hypr_events::run(hypr_events, shutdown_rx, health).await;
            ("hypr-events", Ok(()))
        }
    });

    let attributed_class = Arc::new(Mutex::new(String::new()));
    let focus_state = focus::FocusState::default();
    auxiliary.spawn({
        let hypr_rx = hypr_events.subscribe();
        let attributed_class = Arc::clone(&attributed_class);
        let focus_state = focus_state.clone();
        let resolver = Arc::clone(&resolver);
        let events = events.clone();
        let shutdown_rx = shutdown_rx.clone();
        let health = health.clone();
        async move {
            (
                "focus tracker",
                focus::run(
                    hypr_rx,
                    attributed_class,
                    focus_state,
                    resolver,
                    events,
                    shutdown_rx,
                    health,
                )
                .await,
            )
        }
    });

    let power_history = power::PowerHistory::default();
    if let Some(sources) = power::Sources::discover() {
        let history = power_history.clone();
        let events = events.clone();
        let resolver = Arc::clone(&resolver);
        let panel_hz = Arc::clone(&panel_hz);
        let bus = system_bus.clone();
        let shutdown_rx = shutdown_rx.clone();
        let health = health.clone();
        auxiliary.spawn(async move {
            (
                "power sampler",
                power::run(
                    sources,
                    power::PowerContext {
                        attributed_class,
                        resolver,
                        panel_hz,
                        history,
                        events,
                        system_bus: bus,
                    },
                    shutdown_rx,
                    health,
                )
                .await,
            )
        });
    }

    auxiliary.spawn({
        let hypr_rx = hypr_events.subscribe();
        let hypr = hypr.clone();
        let theme = theme.clone();
        let panel_hz = Arc::clone(&panel_hz);
        let shutdown_rx = shutdown_rx.clone();
        let health = health.clone();
        async move {
            (
                "monitor watcher",
                monitors::run(hypr_rx, hypr, theme, panel_hz, shutdown_rx, health).await,
            )
        }
    });

    {
        let shutdown = Arc::clone(&shutdown);
        let halted = Arc::new(Mutex::new(false));
        auxiliary.spawn({
            let halted = halted.clone();
            let bus = system_bus.clone();
            let shutdown_rx = shutdown_rx.clone();
            let health = health.clone();
            async move {
                (
                    "session shutdown watch",
                    session::halt_on_shutdown(halted, bus, shutdown_rx, health).await,
                )
            }
        });
        health.set_running("session recorder");
        auxiliary.spawn_blocking({
            let health = health.clone();
            move || {
                let res = session::run(shutdown, halted);
                if let Err(ref error) = res {
                    health.set_degraded("session recorder", error.to_string());
                } else {
                    health.set_stopped("session recorder");
                }
                ("session recorder", res)
            }
        });
    }

    auxiliary.spawn({
        let night_light = night_light.clone();
        let bus = system_bus.clone();
        let shutdown_rx = shutdown_rx.clone();
        let health = health.clone();
        async move {
            (
                "solar scheduler",
                solar::run(night_light, bus, shutdown_rx, health).await,
            )
        }
    });

    let airdrop = airdrop::AirDropController::new(events.clone());
    auxiliary.spawn({
        let airdrop = airdrop.clone();
        let bus = system_bus.clone();
        let shutdown_rx = shutdown_rx.clone();
        let health = health.clone();
        async move {
            (
                "airdrop",
                airdrop::run(airdrop, bus, shutdown_rx, health).await,
            )
        }
    });

    let airpods = airpods::AirPodsController::new(events.clone());
    auxiliary.spawn({
        let airpods = airpods.clone();
        let bus = system_bus.clone();
        let shutdown_rx = shutdown_rx.clone();
        let health = health.clone();
        async move {
            (
                "airpods watcher",
                airpods::run(airpods, bus, shutdown_rx, health).await,
            )
        }
    });

    let supervisor_health = health.clone();
    let supervisor = tokio::spawn(async move {
        while let Some(task) = auxiliary.join_next().await {
            report_auxiliary_exit(task, &supervisor_health);
        }
    });

    {
        let theme = theme.clone();
        match tokio::task::spawn_blocking(move || solar::boot_catch_up(&theme)).await {
            Ok(Err(error)) => tracing::warn!(error = %error, "dark-hint boot catch-up failed"),
            Err(error) => tracing::warn!(error = %error, "dark-hint boot catch-up did not run"),
            Ok(Ok(())) => {}
        }
    }

    let mut server = tokio::spawn({
        let context = server::ServerContext {
            airdrop,
            airpods,
            night_light: night_light.clone(),
            theme: theme.clone(),
            hypr: hypr.clone(),
            session,
            brightness: brightness::BrightnessController::new(events.clone()),
            power: power_history,
            focus: focus_state,
            health: health.clone(),
            started_at: Instant::now(),
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
fn report_auxiliary_exit(
    task: Result<(&'static str, crate::Result<()>), tokio::task::JoinError>,
    health: &SubsystemHealth,
) {
    match task {
        Ok((name, Ok(()))) => {
            tracing::info!(subsystem = name, "auxiliary task exited");
            health.set_stopped(name);
        }
        Ok((name, Err(error))) => {
            tracing::error!(subsystem = name, error = %error, "auxiliary task failed");
            health.set_degraded(name, error.to_string());
        }
        Err(error) => tracing::error!(error = %error, "auxiliary task join failed"),
    }
}
