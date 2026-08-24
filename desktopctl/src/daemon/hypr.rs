//! Serializes hypr override mutations (input runtime settings, the animation
//! override file) so two writers can never interleave a read-modify-write.
//! The operations are sub-second, so a plain mutex held across each one is
//! fine — unlike theme applies.

use crate::{daemon::server::Events, displays, hypr};
use serde_json::Value;
use std::{
    io,
    sync::{Arc, Mutex},
};

#[derive(Clone)]
pub struct HyprController {
    lock: Arc<Mutex<()>>,
    events: Events,
}

impl HyprController {
    pub fn new(events: Events) -> Self {
        Self {
            lock: Arc::new(Mutex::new(())),
            events,
        }
    }

    pub fn input_status(&self) -> crate::Result<Value> {
        let state = hypr::load_effective_input_state()?;
        Ok(serde_json::to_value(state)?)
    }

    pub fn input_set(&self, key: &str, value: &str) -> crate::Result<Value> {
        let state = {
            let _guard = self.lock_serialized()?;
            let setting = hypr::InputSetting::parse(key)?;
            hypr::set_input_value(setting, value)?
        };

        let state = serde_json::to_value(state)?;
        self.events.publish("hypr_input.changed", state.clone());
        Ok(serde_json::json!({ "state": state }))
    }

    pub fn monitors_status(&self) -> crate::Result<Value> {
        Ok(serde_json::to_value(displays::status()?)?)
    }

    pub fn monitors_primary(&self, selector: &str) -> crate::Result<Value> {
        let status = {
            let _guard = self.lock_serialized()?;
            displays::set_primary(selector)?
        };
        self.publish_monitors(status)
    }

    pub fn monitors_layout(&self, positions: &Value) -> crate::Result<Value> {
        let status = {
            let _guard = self.lock_serialized()?;
            displays::save_positions(serde_json::from_value(positions.clone())?)?
        };
        self.publish_monitors(status)
    }

    /// Reconciling publishes as well: a monitor coming or going can change the
    /// effective primary without anyone having asked for a change.
    pub fn monitors_reconcile(&self) -> crate::Result<Value> {
        let status = {
            let _guard = self.lock_serialized()?;
            displays::reconcile()?
        };
        self.publish_monitors(status)
    }

    fn publish_monitors(&self, status: displays::DisplayStatus) -> crate::Result<Value> {
        let status = serde_json::to_value(status)?;
        self.events.publish("hypr_monitors.changed", status.clone());
        Ok(status)
    }

    // Animations publish no events: the shell has no live subscriber for
    // them (the editor was deliberately not rebuilt).
    pub fn animations_save(&self, payload: &Value) -> crate::Result<Value> {
        let _guard = self.lock_serialized()?;
        hypr::save_animations(&serde_json::to_string(payload)?)?;
        Ok(serde_json::json!({}))
    }

    pub fn animations_clear(&self) -> crate::Result<Value> {
        let _guard = self.lock_serialized()?;
        hypr::clear_animations()?;
        Ok(serde_json::json!({}))
    }

    fn lock_serialized(&self) -> crate::Result<std::sync::MutexGuard<'_, ()>> {
        self.lock
            .lock()
            .map_err(|_| io::Error::other("hypr controller lock poisoned").into())
    }
}
