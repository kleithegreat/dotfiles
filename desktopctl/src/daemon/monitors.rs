//! Everything a display coming or going has to trigger: the numbered
//! workspaces follow whichever output is primary now, the focused output is
//! pulled back onto that set, and the new output gets the wallpaper — awww
//! paints an output it has not seen before black and never revisits it.

use crate::{
    daemon::{
        SubsystemHealth,
        hypr::HyprController,
        hypr_events::HyprEvent,
        theme::{ThemeController, ThemeJob},
    },
    hypr,
    theme::ApplyScope,
};
use std::{
    sync::{Arc, Mutex},
    time::Duration as StdDuration,
};
use tokio::sync::{broadcast, watch};

/// Hyprland assigns an output's default workspace on connect and finishes
/// placing pinned workspaces on the next event-loop pass, so let the topology
/// settle before reading it back.
const SETTLE_DELAY: StdDuration = StdDuration::from_millis(300);

pub type SharedPanelHz = Arc<Mutex<Option<f64>>>;

pub(crate) fn refresh_panel_hz(panel_hz: &SharedPanelHz) {
    let rate = hypr::query_monitors().ok().and_then(|monitors| {
        monitors
            .into_iter()
            .find(|monitor| monitor.is_internal() && !monitor.disabled && monitor.dpms_status)
            .map(|monitor| monitor.refresh_rate)
    });
    if let Ok(mut guard) = panel_hz.lock() {
        *guard = rate;
    }
}

pub async fn run(
    mut hypr_rx: broadcast::Receiver<HyprEvent>,
    hypr: HyprController,
    theme: ThemeController,
    panel_hz: SharedPanelHz,
    mut shutdown: watch::Receiver<bool>,
    health: SubsystemHealth,
) -> crate::Result<()> {
    health.set_running("monitor watcher");

    loop {
        let wallpaper = tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    health.set_stopped("monitor watcher");
                    return Ok(());
                }
                continue;
            }
            event = hypr_rx.recv() => match event {
                Ok(HyprEvent::Connected) => false,
                Ok(HyprEvent::Line(line))
                    if line.starts_with("monitoradded") || line.starts_with("monitorremoved") =>
                {
                    true
                }
                Ok(HyprEvent::Line(line)) if line.starts_with("configreloaded") => {
                    let hz = panel_hz.clone();
                    let _ = tokio::task::spawn_blocking(move || refresh_panel_hz(&hz)).await;
                    continue;
                }
                Ok(HyprEvent::Line(_)) => continue,
                Err(broadcast::error::RecvError::Lagged(_)) => true,
                Err(broadcast::error::RecvError::Closed) => {
                    health.set_stopped("monitor watcher");
                    return Ok(());
                }
            }
        };

        // Drain burst topology events before waiting to settle.
        let mut apply_wallpaper = wallpaper;
        while let Ok(queued) = hypr_rx.try_recv() {
            if let HyprEvent::Line(line) = queued
                && (line.starts_with("monitoradded") || line.starts_with("monitorremoved"))
            {
                apply_wallpaper = true;
            }
        }

        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    health.set_stopped("monitor watcher");
                    return Ok(());
                }
            }
            () = tokio::time::sleep(SETTLE_DELAY) => {}
        }

        let hypr_clone = hypr.clone();
        let hz_clone = panel_hz.clone();
        let outcome = tokio::task::spawn_blocking(move || {
            let mut warnings = Vec::new();
            if let Err(error) = hypr_clone.monitors_reconcile() {
                tracing::warn!(error = %error, "display reconcile failed");
                warnings.push(format!("reconcile: {error}"));
            }
            if let Err(error) = hypr::reclaim_workspaces() {
                tracing::warn!(error = %error, "workspace reclaim failed");
                warnings.push(format!("reclaim: {error}"));
            }
            refresh_panel_hz(&hz_clone);
            warnings
        })
        .await;

        let mut warnings = outcome.unwrap_or_else(|error| vec![error.to_string()]);
        if apply_wallpaper
            && let Err(error) = theme
                .request(ThemeJob::Apply {
                    scope: ApplyScope::Wallpaper,
                })
                .await
        {
            tracing::warn!(error = %error, "wallpaper reapply failed");
            warnings.push(format!("wallpaper: {error}"));
        }

        if warnings.is_empty() {
            health.set_running("monitor watcher");
        } else {
            health.set_degraded("monitor watcher", warnings.join("; "));
        }
    }
}
