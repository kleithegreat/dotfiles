use crate::hypr;
use std::{
    sync::{
        Arc,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::Duration as StdDuration,
};

/// Hyprland assigns an output's default workspace on connect and finishes
/// placing pinned workspaces on the next event-loop pass, so let the topology
/// settle before reading it back.
const SETTLE_DELAY: StdDuration = StdDuration::from_millis(300);

/// Keep the focused output on the numbered workspace set across session start
/// and any output coming or going.
pub fn run(shutdown: Arc<AtomicBool>) -> crate::Result<()> {
    hypr::watch_event_socket(&shutdown, reclaim, |line| {
        if !line.starts_with("monitoradded") && !line.starts_with("monitorremoved") {
            return;
        }

        if shutdown.load(Ordering::SeqCst) {
            return;
        }
        thread::sleep(SETTLE_DELAY);
        reclaim();
    });

    Ok(())
}

fn reclaim() {
    if let Err(error) = hypr::reclaim_workspaces() {
        eprintln!("desktopctl: workspace reclaim failed: {error}");
    }
}
