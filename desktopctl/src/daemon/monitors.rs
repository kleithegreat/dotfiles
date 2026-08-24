use crate::{
    daemon::{hypr::HyprController, theme::ThemeController, theme::ThemeJob},
    hypr,
    theme::ApplyScope,
};
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

/// Everything a display coming or going has to trigger: the numbered
/// workspaces follow whichever output is primary now, the focused output is
/// pulled back onto that set, and the new output gets the wallpaper — awww
/// paints an output it has not seen before black and never revisits it.
pub fn run(
    shutdown: Arc<AtomicBool>,
    hypr: HyprController,
    theme: ThemeController,
) -> crate::Result<()> {
    let settled = |shutdown: &AtomicBool| {
        if shutdown.load(Ordering::SeqCst) {
            return;
        }
        thread::sleep(SETTLE_DELAY);
        reconcile(&hypr);
        reclaim();
        reapply_wallpaper(&theme);
    };

    hypr::watch_event_socket(
        &shutdown,
        // A daemon restart is a topology event too: nothing else re-establishes
        // the workspace pins this process is the only writer of.
        || settled(&shutdown),
        |line| {
            if line.starts_with("monitoradded") || line.starts_with("monitorremoved") {
                settled(&shutdown);
            }
        },
    );

    Ok(())
}

fn reconcile(hypr: &HyprController) {
    if let Err(error) = hypr.monitors_reconcile() {
        eprintln!("desktopctl: display reconcile failed: {error}");
    }
}

fn reclaim() {
    if let Err(error) = hypr::reclaim_workspaces() {
        eprintln!("desktopctl: workspace reclaim failed: {error}");
    }
}

fn reapply_wallpaper(theme: &ThemeController) {
    if let Err(error) = theme.request_blocking(ThemeJob::Apply {
        scope: ApplyScope::Wallpaper,
    }) {
        eprintln!("desktopctl: wallpaper reapply failed: {error}");
    }
}
