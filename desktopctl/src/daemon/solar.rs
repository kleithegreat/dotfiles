use crate::{daemon::night_light::Controller, solar};
use std::{io, time::Duration as StdDuration};
use tokio::{
    signal::unix::{SignalKind, signal},
    sync::watch,
};

pub async fn run(controller: Controller, mut shutdown: watch::Receiver<bool>) -> crate::Result<()> {
    let mut sigusr1 = signal(SignalKind::user_defined1())?;

    loop {
        if *shutdown.borrow() {
            return Ok(());
        }

        let next_event = solar_tick(controller.clone()).await?;

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
async fn solar_tick(controller: Controller) -> crate::Result<solar::SolarEvent> {
    tokio::task::spawn_blocking(move || {
        let location = solar::resolve_location()?;
        let status = solar::status_for_now(chrono::Local::now(), location);
        let next_event = solar::next_event(&status);

        controller.update_solar_status(status)?;
        if let Err(error) = controller.reconcile() {
            eprintln!("solar reconcile failed (will retry at next event or repair tick): {error}");
        }

        Ok(next_event)
    })
    .await
    .map_err(|error| io::Error::other(format!("solar tick task join failed: {error}")))?
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
}
