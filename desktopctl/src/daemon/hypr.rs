//! Serializes hypr override mutations (input runtime settings, animation and
//! keybind override files) so two writers can never interleave a
//! read-modify-write. The operations are sub-second, so a plain mutex held
//! across each one is fine — unlike theme applies.

use crate::{daemon::server::Events, hypr};
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

    // Animations/keybinds publish no events: the shell has no live
    // subscriber for them (the editors were deliberately not rebuilt).
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

    pub fn keybinds_save(&self, payload: &Value) -> crate::Result<Value> {
        let _guard = self.lock_serialized()?;
        hypr::save_keybinds(&serde_json::to_string(payload)?)?;
        Ok(serde_json::json!({}))
    }

    pub fn keybinds_clear(&self) -> crate::Result<Value> {
        let _guard = self.lock_serialized()?;
        hypr::clear_keybinds()?;
        Ok(serde_json::json!({}))
    }

    fn lock_serialized(&self) -> crate::Result<std::sync::MutexGuard<'_, ()>> {
        self.lock
            .lock()
            .map_err(|_| io::Error::other("hypr controller lock poisoned").into())
    }
}
