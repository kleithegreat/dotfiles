use crate::{
    daemon::{
        night_light::Controller,
        session::LoginProxy,
        theme::{ThemeController, ThemeJob},
    },
    solar,
    theme::DarkHintOrigin,
};
use chrono::{DateTime, Local};
use futures_util::StreamExt;
use std::{io, time::Duration as StdDuration};
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::watch,
};

pub async fn run(
    controller: Controller,
    system_bus: Option<zbus::Connection>,
    mut shutdown: watch::Receiver<bool>,
    health: crate::daemon::SubsystemHealth,
) -> crate::Result<()> {
    let mut sigusr1 = signal(SignalKind::user_defined1())?;
    let mut sleep_signals = match system_bus {
        Some(ref bus) => match LoginProxy::new(bus).await {
            Ok(proxy) => proxy.receive_prepare_for_sleep().await.ok(),
            Err(error) => {
                tracing::warn!(error = %error, "login1 proxy unavailable for solar scheduler");
                None
            }
        },
        None => None,
    };

    loop {
        if *shutdown.borrow() {
            health.set_stopped("solar scheduler");
            return Ok(());
        }

        let next_event = solar_tick(controller.clone(), &health).await?;

        let event_sleep =
            tokio::time::sleep(duration_until(next_event).max(StdDuration::from_millis(50)));
        let recompute_sleep = tokio::time::sleep(StdDuration::from_secs(2 * 60 * 60));
        tokio::pin!(event_sleep);
        tokio::pin!(recompute_sleep);

        loop {
            tokio::select! {
                changed = shutdown.changed() => {
                    if changed.is_err() || *shutdown.borrow() {
                        health.set_stopped("solar scheduler");
                        return Ok(());
                    }
                }
                _ = sigusr1.recv() => break,
                _ = &mut recompute_sleep => break,
                _ = &mut event_sleep => break,
                signal = async {
                    match sleep_signals.as_mut() {
                        Some(stream) => stream.next().await,
                        None => std::future::pending().await,
                    }
                } => match signal {
                    Some(signal) => {
                        if let Ok(args) = signal.args()
                            && !args.start
                        {
                            break;
                        }
                    }
                    None => sleep_signals = None,
                }
            }
        }
    }
}

/// Run one blocking solar recompute/reconcile cycle off the async runtime.
async fn solar_tick(
    controller: Controller,
    health: &crate::daemon::SubsystemHealth,
) -> crate::Result<DateTime<Local>> {
    let health = health.clone();
    tokio::task::spawn_blocking(move || {
        let location = solar::resolve_location()?;
        let status = solar::status_for_now(chrono::Local::now(), location);
        let next_event = solar::next_event(&status);

        controller.update_solar_status(status)?;
        match controller.reconcile() {
            Ok(_) => health.set_running("solar scheduler"),
            Err(error) => {
                tracing::warn!(
                    error = %error,
                    "solar reconcile failed (will retry at next event or repair tick)"
                );
                health.set_degraded("solar scheduler", error.to_string());
            }
        }

        Ok(next_event)
    })
    .await
    .map_err(|error| io::Error::other(format!("solar tick task join failed: {error}")))?
}

/// Apply a dark-hint edge crossed while the machine was off. It runs before
/// the daemon serves anything, so apps the session restores launch with the
/// right value instead of the one they were closed with.
pub fn boot_catch_up(theme: &ThemeController) -> crate::Result<()> {
    let state = crate::theme::resolve::load_state()?;
    let manual_at = state
        .extra
        .get(crate::theme::DARK_HINT_MANUAL_AT_KEY)
        .and_then(|value| value.as_str())
        .and_then(parse_manual_timestamp);
    let now = chrono::Local::now();
    let window_start = solar::dark_window_start(now);

    if let Some(enabled) = catch_up_decision(
        state.dark_hint,
        manual_at,
        window_start,
        solar::in_dark_window(now),
    ) {
        theme.request_blocking(ThemeJob::Set {
            key: "dark_hint".to_owned(),
            value: serde_json::Value::Bool(enabled),
            origin: DarkHintOrigin::Scheduled,
        })?;
    }

    Ok(())
}

fn parse_manual_timestamp(raw: &str) -> Option<DateTime<Local>> {
    DateTime::parse_from_rfc3339(raw)
        .ok()
        .map(|when| when.with_timezone(&Local))
}

/// Whether the boot catch-up should write the schedule's dark_hint value. A
/// manual write recorded inside the current window wins; otherwise the
/// schedule reasserts only when the persisted value disagrees with it.
fn catch_up_decision(
    persisted_dark_hint: bool,
    manual_at: Option<DateTime<Local>>,
    window_start: DateTime<Local>,
    schedule_dark: bool,
) -> Option<bool> {
    if manual_at.is_some_and(|at| at >= window_start) {
        return None;
    }

    (persisted_dark_hint != schedule_dark).then_some(schedule_dark)
}

fn duration_until(when: chrono::DateTime<chrono::Local>) -> StdDuration {
    let now = chrono::Local::now();
    let duration = when.signed_duration_since(now);
    if duration <= chrono::Duration::zero() {
        return StdDuration::ZERO;
    }

    duration.to_std().unwrap_or(StdDuration::ZERO)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn catch_up_decision_matrix() {
        let window_start = chrono::Local::now();
        let inside = Some(window_start + chrono::Duration::minutes(30));
        let before = Some(window_start - chrono::Duration::minutes(30));

        // A manual write inside the current window always wins.
        assert_eq!(catch_up_decision(false, inside, window_start, true), None);
        assert_eq!(catch_up_decision(true, inside, window_start, false), None);

        // Superseded by an edge: the schedule reasserts on disagreement.
        assert_eq!(
            catch_up_decision(false, before, window_start, true),
            Some(true)
        );
        assert_eq!(catch_up_decision(true, before, window_start, true), None);

        // No manual record: plain schedule reassertion on disagreement.
        assert_eq!(
            catch_up_decision(false, None, window_start, true),
            Some(true)
        );
        assert_eq!(
            catch_up_decision(true, None, window_start, false),
            Some(false)
        );
        assert_eq!(catch_up_decision(true, None, window_start, true), None);
    }
}
