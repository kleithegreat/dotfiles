use crate::{
    daemon::{
        server::Events,
        theme::{ThemeController, ThemeJob},
    },
    night_light::{
        NightLightMode, NightLightStatus, ensure_hyprsunset_running, hyprsunset_process_state,
        normalize_temperature, stop_hyprsunset,
    },
    solar,
    theme::DarkHintOrigin,
};
use std::{
    io,
    sync::{Arc, Mutex, MutexGuard},
};

#[derive(Clone)]
pub struct Controller {
    state: Arc<Mutex<State>>,
    /// Serializes subprocess/theme handoffs without holding `state` across I/O.
    reconcile_lock: Arc<Mutex<()>>,
    /// Scheduled dark_hint edges route through the theme worker so the
    /// daemon has exactly one writer for theme state.
    theme: ThemeController,
    events: Events,
}

struct State {
    mode: NightLightMode,
    manual_temperature: i32,
    solar_status: Option<solar::SolarStatus>,
    pending_dark_hint_target: Option<bool>,
}

struct DesiredState {
    running: bool,
    temperature: i32,
}

impl Controller {
    pub fn new(theme: ThemeController, events: Events) -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                mode: NightLightMode::Auto,
                manual_temperature: solar::HYPRSUNSET_TEMP,
                solar_status: None,
                pending_dark_hint_target: None,
            })),
            reconcile_lock: Arc::new(Mutex::new(())),
            theme,
            events,
        }
    }

    /// Record the latest solar status. Only a dark-window *edge* queues a
    /// scheduled dark_hint write: asserting on every tick (or on the first
    /// tick after a daemon restart) would clobber manual values, which win
    /// until the next edge. Reboot coverage is the solar task's separate
    /// boot catch-up, gated on the recorded manual-write time.
    pub fn update_solar_status(&self, status: solar::SolarStatus) -> crate::Result<()> {
        let mut state = self.lock_state()?;
        if let Some(enabled) = dark_hint_transition(state.solar_status.as_ref(), &status) {
            state.pending_dark_hint_target = Some(enabled);
        }
        state.solar_status = Some(status);
        Ok(())
    }

    pub fn reconcile(&self) -> crate::Result<NightLightStatus> {
        let _reconcile = self.lock_reconcile()?;
        self.apply_and_publish(|_| Ok(()))
    }

    pub fn set_mode(
        &self,
        mode: NightLightMode,
        temperature: Option<i32>,
    ) -> crate::Result<NightLightStatus> {
        let normalized_temperature = match temperature {
            Some(temperature) => Some(normalize_temperature(temperature)?),
            None => None,
        };

        let _reconcile = self.lock_reconcile()?;
        self.apply_and_publish(|state| {
            state.mode = mode;
            if let Some(temperature) = normalized_temperature {
                state.manual_temperature = temperature;
            }
            Ok(())
        })
    }

    pub fn toggle(&self) -> crate::Result<NightLightStatus> {
        let _reconcile = self.lock_reconcile()?;
        let mode = if hyprsunset_process_state().running {
            NightLightMode::Off
        } else {
            NightLightMode::On
        };
        self.apply_and_publish(|state| {
            state.mode = mode;
            Ok(())
        })
    }

    pub fn status(&self) -> crate::Result<NightLightStatus> {
        let (mode, target_temp, solar_status) = {
            let state = self.lock_state()?;
            let solar_status = current_solar_status(&state)?;
            (state.mode, target_temperature(&state), solar_status)
        };
        NightLightStatus::observe(mode, target_temp, &solar_status)
    }

    fn apply_and_publish(
        &self,
        mutate: impl FnOnce(&mut State) -> crate::Result<()>,
    ) -> crate::Result<NightLightStatus> {
        let (mode, target_temp, solar_status, desired, pending_dark_hint) = {
            let mut state = self.lock_state()?;
            mutate(&mut state)?;
            let solar_status = current_solar_status(&state)?;
            let desired = desired_state(state.mode, state.manual_temperature, &solar_status);
            (
                state.mode,
                target_temperature(&state),
                solar_status,
                desired,
                state.pending_dark_hint_target,
            )
        };

        apply_desired_state(&desired)?;

        if let Some(enabled) = pending_dark_hint {
            self.theme.request_blocking(ThemeJob::Set {
                key: "dark_hint".to_owned(),
                value: serde_json::Value::Bool(enabled),
                origin: DarkHintOrigin::Scheduled,
            })?;
            let mut state = self.lock_state()?;
            if state.pending_dark_hint_target == Some(enabled) {
                state.pending_dark_hint_target = None;
            }
        }

        let status = NightLightStatus::observe(mode, target_temp, &solar_status)?;
        self.events.publish(
            "night_light.changed",
            serde_json::to_value(&status).unwrap_or(serde_json::Value::Null),
        );

        Ok(status)
    }

    fn lock_state(&self) -> crate::Result<MutexGuard<'_, State>> {
        self.state
            .lock()
            .map_err(|_| io::Error::other("night-light state lock poisoned").into())
    }

    fn lock_reconcile(&self) -> crate::Result<MutexGuard<'_, ()>> {
        self.reconcile_lock
            .lock()
            .map_err(|_| io::Error::other("night-light reconcile lock poisoned").into())
    }
}

fn current_solar_status(state: &State) -> crate::Result<solar::SolarStatus> {
    if let Some(status) = &state.solar_status {
        return Ok(status.clone());
    }

    let location = solar::resolve_location()?;
    Ok(solar::status_for_now(chrono::Local::now(), location))
}

fn desired_state(
    mode: NightLightMode,
    manual_temperature: i32,
    solar_status: &solar::SolarStatus,
) -> DesiredState {
    match mode {
        NightLightMode::Auto => DesiredState {
            running: solar_status.is_night,
            temperature: solar::HYPRSUNSET_TEMP,
        },
        NightLightMode::On => DesiredState {
            running: true,
            temperature: manual_temperature,
        },
        NightLightMode::Off => DesiredState {
            running: false,
            temperature: manual_temperature,
        },
    }
}

fn dark_hint_transition(
    previous: Option<&solar::SolarStatus>,
    current: &solar::SolarStatus,
) -> Option<bool> {
    // No previous status is daemon startup, not an edge; the boot catch-up owns that.
    let previous = previous?;
    (previous.is_dark != current.is_dark).then_some(current.is_dark)
}

fn target_temperature(state: &State) -> i32 {
    match state.mode {
        NightLightMode::Auto => solar::HYPRSUNSET_TEMP,
        NightLightMode::On | NightLightMode::Off => state.manual_temperature,
    }
}

fn apply_desired_state(desired: &DesiredState) -> crate::Result<()> {
    if desired.running {
        ensure_hyprsunset_running(desired.temperature)?;
    } else {
        stop_hyprsunset()?;
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_controller() -> Controller {
        let events = Events::new();
        let theme = ThemeController::spawn(events.clone());
        Controller::new(theme, events)
    }

    fn sample_solar_status(is_night: bool, is_dark: bool) -> solar::SolarStatus {
        let now = chrono::Local::now();
        solar::SolarStatus {
            location: solar::Coordinates {
                latitude: solar::DEFAULT_LATITUDE,
                longitude: solar::DEFAULT_LONGITUDE,
            },
            sunrise: Some(now),
            sunset: Some(now),
            is_night,
            is_dark,
            next_sunrise: Some(now),
            next_sunset: Some(now),
            next_dark_on: now,
            next_dark_off: now,
        }
    }

    #[tokio::test]
    async fn first_solar_status_never_queues_a_dark_hint_write() {
        // A restart mid-window must not clobber a manual dark_hint.
        let controller = test_controller();
        controller
            .update_solar_status(sample_solar_status(true, true))
            .expect("status update");

        let state = controller.lock_state().expect("state lock");
        assert_eq!(state.pending_dark_hint_target, None);
    }

    #[tokio::test]
    async fn solar_edge_queues_a_scheduled_dark_hint_write() {
        let controller = test_controller();
        controller
            .update_solar_status(sample_solar_status(true, false))
            .expect("first status");
        controller
            .update_solar_status(sample_solar_status(true, true))
            .expect("edge status");

        let state = controller.lock_state().expect("state lock");
        assert_eq!(state.pending_dark_hint_target, Some(true));
    }

    #[tokio::test]
    async fn set_mode_rejects_invalid_temperature_without_mutating_mode() {
        let controller = test_controller();
        let error = controller.set_mode(NightLightMode::On, Some(9999));

        assert!(error.is_err());
        let state = controller.lock_state().expect("state lock");
        assert_eq!(state.mode, NightLightMode::Auto);
        assert_eq!(state.manual_temperature, solar::HYPRSUNSET_TEMP);
    }
}
