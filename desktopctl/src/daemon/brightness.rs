//! Owns dim/restore state in memory and serializes hardware writes, replacing
//! the /tmp pid file and runtime-dir DDC state file whose races could lose
//! the pre-dim level. A second dim while dimmed is a no-op (the original
//! level is preserved); restore cancels an in-flight ramp before restoring.

use crate::{brightness, daemon::server::Events};
use serde_json::Value;
use std::{
    collections::HashMap,
    io,
    sync::{
        Arc, Mutex, MutexGuard,
        atomic::{AtomicBool, Ordering},
    },
};

#[derive(Clone)]
pub struct BrightnessController {
    inner: Arc<Inner>,
    events: Events,
}

struct Inner {
    /// Serializes every hardware write, dim ramps included.
    op: Mutex<Saved>,
    /// Breaks a dim ramp between steps so restore never waits the full ramp.
    abort_dim: AtomicBool,
}

type Saved = HashMap<String, brightness::SavedLevel>;

impl BrightnessController {
    pub fn new(events: Events) -> Self {
        Self {
            inner: Arc::new(Inner {
                op: Mutex::new(HashMap::new()),
                abort_dim: AtomicBool::new(false),
            }),
            events,
        }
    }

    pub fn status(&self) -> crate::Result<Value> {
        brightness::status_json()
    }

    pub fn set(&self, device: Option<&str>, percent: u16) -> crate::Result<Value> {
        let device_status = {
            let _guard = self.lock_op()?;
            brightness::set_core(device, percent)?
        };
        self.publish(&device_status, false);
        Ok(serde_json::json!({ "devices": [device_status] }))
    }

    pub fn step(&self, device: Option<&str>, direction: f64) -> crate::Result<Value> {
        let device_status = {
            let _guard = self.lock_op()?;
            brightness::step_core(device, direction)?
        };
        // Hotkey steps carry the OSD flag; the shell shows the overlay from
        // this event instead of the old `qs ipc call` round-trip.
        self.publish(&device_status, true);
        Ok(serde_json::json!({ "devices": [device_status] }))
    }

    pub fn dim(&self, device: Option<&str>) -> crate::Result<Value> {
        let key = brightness::resolve_device_key(device)?;

        self.inner.abort_dim.store(false, Ordering::Relaxed);
        let mut saved = self.lock_op()?;
        // A dim while already dimmed must not overwrite the saved pre-dim
        // level with the dimmed one.
        if saved.contains_key(&key) {
            return Ok(serde_json::json!({ "already_dimmed": true }));
        }
        let level = brightness::dim_core(device, &self.inner.abort_dim)?;
        saved.insert(key, level);
        Ok(serde_json::json!({}))
    }

    pub fn restore(&self, device: Option<&str>) -> crate::Result<Value> {
        // Break any in-flight ramp first; it holds the op mutex and checks
        // the flag between 50ms steps.
        self.inner.abort_dim.store(true, Ordering::Relaxed);
        let key = brightness::resolve_device_key(device)?;

        let restored = {
            let mut saved = self.lock_op()?;
            match saved.remove(&key) {
                Some(level) => Some(brightness::restore_saved(&level)?),
                // Nothing saved: restore is idempotent, not an error.
                None => None,
            }
        };

        if let Some(device_status) = restored {
            self.publish(&device_status, false);
        }
        Ok(serde_json::json!({}))
    }

    fn publish(&self, device_status: &Value, osd: bool) {
        self.events.publish(
            "brightness.changed",
            serde_json::json!({ "devices": [device_status], "osd": osd }),
        );
    }

    fn lock_op(&self) -> crate::Result<MutexGuard<'_, Saved>> {
        self.inner
            .op
            .lock()
            .map_err(|_| io::Error::other("brightness controller lock poisoned").into())
    }
}
