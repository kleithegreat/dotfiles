use crate::{daemon::night_light::Controller, solar};
use std::time::Duration as StdDuration;
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

        let location = solar::resolve_location()?;
        let status = solar::status_for_now(chrono::Local::now(), location);
        let next_event = solar::next_event(&status);

        controller.update_solar_status(status)?;
        controller.reconcile()?;

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

fn duration_until(when: chrono::DateTime<chrono::Local>) -> StdDuration {
    let now = chrono::Local::now();
    let duration = when.signed_duration_since(now);
    if duration <= chrono::Duration::zero() {
        return StdDuration::ZERO;
    }

    duration.to_std().unwrap_or(StdDuration::ZERO)
}
