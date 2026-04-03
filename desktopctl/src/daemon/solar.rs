use crate::{
    hypr,
    solar::{self, SolarEventKind},
    theme,
};
use std::{process::Command, time::Duration as StdDuration};
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::watch,
};

pub async fn run(mut shutdown: watch::Receiver<bool>) -> crate::Result<()> {
    let mut sigusr1 = signal(SignalKind::user_defined1())?;

    loop {
        if *shutdown.borrow() {
            return Ok(());
        }

        let location = solar::resolve_location()?;
        let status = solar::status_for_now(chrono::Local::now(), location);
        apply_current_state(&status)?;
        let next_event = solar::next_event(&status);

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
            _ = &mut event_sleep => {
                fire_event(next_event.kind)?;
            }
        }
    }
}

fn apply_current_state(status: &solar::SolarStatus) -> crate::Result<()> {
    if status.is_night {
        start_hyprsunset()?;
    } else {
        stop_hyprsunset()?;
    }

    set_dark_hint(status.is_dark)
}

fn fire_event(event: SolarEventKind) -> crate::Result<()> {
    match event {
        SolarEventKind::Sunrise => {
            stop_hyprsunset()?;
            set_dark_hint(false)?;
        }
        SolarEventKind::Sunset => start_hyprsunset()?,
        SolarEventKind::DarkOn => set_dark_hint(true)?,
    }

    Ok(())
}

fn start_hyprsunset() -> crate::Result<()> {
    if Command::new("pgrep")
        .args(["-x", "hyprsunset"])
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
    {
        return Ok(());
    }

    let command = format!("hyprsunset -t {}", solar::HYPRSUNSET_TEMP);
    hypr::dispatch(&["exec", &command])
}

fn stop_hyprsunset() -> crate::Result<()> {
    let _ = Command::new("pkill").args(["-x", "hyprsunset"]).output();
    Ok(())
}

fn set_dark_hint(enabled: bool) -> crate::Result<()> {
    theme::set_dark_hint(enabled)
}

fn duration_until(when: chrono::DateTime<chrono::Local>) -> StdDuration {
    let now = chrono::Local::now();
    let duration = when.signed_duration_since(now);
    if duration <= chrono::Duration::zero() {
        return StdDuration::ZERO;
    }

    duration.to_std().unwrap_or(StdDuration::ZERO)
}
