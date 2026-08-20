use crate::{
    daemon::{
        night_light::Controller,
        theme::{ThemeController, ThemeJob},
    },
    solar,
    theme::DarkHintOrigin,
};
use chrono::{DateTime, Local};
use std::{io, time::Duration as StdDuration};
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::watch,
};

pub async fn run(
    controller: Controller,
    theme: ThemeController,
    mut shutdown: watch::Receiver<bool>,
) -> crate::Result<()> {
    let mut sigusr1 = signal(SignalKind::user_defined1())?;
    // The boot catch-up runs once, on the first tick: edges cover a running
    // daemon, but a machine that was off across an edge needs the schedule
    // value applied on startup — unless a manual write in the current window
    // outranks it.
    let mut boot_catch_up = Some(theme);

    loop {
        if *shutdown.borrow() {
            return Ok(());
        }

        let next_event = solar_tick(controller.clone(), boot_catch_up.take()).await?;

        let event_sleep = tokio::time::sleep(duration_until(next_event.when));
        let recompute_sleep = tokio::time::sleep(StdDuration::from_secs(2 * 60 * 60));
        tokio::pin!(event_sleep);
        tokio::pin!(recompute_sleep);

        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    return Ok(());
                }
            }
            _ = sigusr1.recv() => {}
            _ = &mut recompute_sleep => {}
            _ = &mut event_sleep => {}
        }
    }
}

/// Run one blocking solar recompute/reconcile cycle off the async runtime,
/// matching the spawn_blocking pattern used by the socket server.
async fn solar_tick(
    controller: Controller,
    boot_catch_up: Option<ThemeController>,
) -> crate::Result<solar::SolarEvent> {
    tokio::task::spawn_blocking(move || {
        let location = solar::resolve_location()?;
        let status = solar::status_for_now(chrono::Local::now(), location);
        let next_event = solar::next_event(&status);

        if let Some(theme) = boot_catch_up
            && let Err(error) = run_boot_catch_up(&status, &theme)
        {
            eprintln!("dark-hint boot catch-up failed: {error}");
        }

        controller.update_solar_status(status)?;
        if let Err(error) = controller.reconcile() {
            eprintln!("solar reconcile failed (will retry at next event or repair tick): {error}");
        }

        Ok(next_event)
    })
    .await
    .map_err(|error| io::Error::other(format!("solar tick task join failed: {error}")))?
}

fn run_boot_catch_up(status: &solar::SolarStatus, theme: &ThemeController) -> crate::Result<()> {
    let state = crate::theme::resolve::load_state()?;
    let manual_at = state
        .extra
        .get(crate::theme::DARK_HINT_MANUAL_AT_KEY)
        .and_then(|value| value.as_str())
        .and_then(parse_manual_timestamp);
    let window_start = solar::dark_window_start(chrono::Local::now());

    if let Some(enabled) =
        catch_up_decision(state.dark_hint, manual_at, window_start, status.is_dark)
    {
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
    fn duration_until_returns_zero_for_past_times() {
        let when = chrono::Local::now() - chrono::Duration::seconds(5);

        assert_eq!(duration_until(when), StdDuration::ZERO);
    }

    #[test]
    fn duration_until_returns_positive_duration_for_future_times() {
        let when = chrono::Local::now() + chrono::Duration::milliseconds(1500);
        let duration = duration_until(when);

        assert!(duration > StdDuration::ZERO);
        assert!(duration <= StdDuration::from_secs(2));
    }

    #[test]
    fn catch_up_decision_matrix() {
        let window_start = chrono::Local::now();
        let inside = Some(window_start + chrono::Duration::minutes(30));
        let before = Some(window_start - chrono::Duration::minutes(30));

        // A manual write inside the current window always wins.
        assert_eq!(catch_up_decision(false, inside, window_start, true), None);
        assert_eq!(catch_up_decision(true, inside, window_start, false), None);

        // A manual write from an earlier window has been superseded by an
        // edge; the schedule reasserts on disagreement.
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

    #[test]
    fn manual_timestamps_round_trip_from_rfc3339() {
        let now = chrono::Local::now();
        let parsed = parse_manual_timestamp(&now.to_rfc3339()).expect("valid timestamp");
        assert_eq!(parsed, now);
        assert_eq!(parse_manual_timestamp("not-a-time"), None);
    }
}
