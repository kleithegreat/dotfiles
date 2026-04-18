use crate::{
    night_light::{
        NightLightMode, NightLightStatus, apply_dark_hint_if_needed, current_dark_hint,
        ensure_hyprsunset_running, hyprsunset_process_state, normalize_temperature,
        stop_hyprsunset,
    },
    solar,
};
use std::{
    io,
    sync::{Arc, Mutex, MutexGuard},
};

#[derive(Clone)]
pub struct Controller {
    state: Arc<Mutex<State>>,
}

struct State {
    mode: NightLightMode,
    manual_temperature: i32,
    solar_status: Option<solar::SolarStatus>,
    pending_dark_hint_enable: bool,
}

struct DesiredState {
    running: bool,
    temperature: i32,
}

impl Controller {
    pub fn new() -> Self {
        Self {
            state: Arc::new(Mutex::new(State {
                mode: NightLightMode::Auto,
                manual_temperature: solar::HYPRSUNSET_TEMP,
                solar_status: None,
                pending_dark_hint_enable: false,
            })),
        }
    }

    pub fn update_solar_status(&self, status: solar::SolarStatus) -> crate::Result<()> {
        let mut state = self.lock_state()?;
        if entered_dark_window(state.solar_status.as_ref(), &status) {
            state.pending_dark_hint_enable = true;
        }
        state.solar_status = Some(status);
        Ok(())
    }

    pub fn reconcile(&self) -> crate::Result<NightLightStatus> {
        let mut state = self.lock_state()?;
        self.reconcile_locked(&mut state)
    }

    pub fn set_mode(
        &self,
        mode: NightLightMode,
        temperature: Option<i32>,
    ) -> crate::Result<NightLightStatus> {
        let mut state = self.lock_state()?;
        state.mode = mode;
        if let Some(temperature) = temperature {
            state.manual_temperature = normalize_temperature(temperature)?;
        }

        self.reconcile_locked(&mut state)
    }

    pub fn toggle(&self) -> crate::Result<NightLightStatus> {
        let mode = if hyprsunset_process_state().running {
            NightLightMode::Off
        } else {
            NightLightMode::On
        };
        self.set_mode(mode, None)
    }

    pub fn status(&self) -> crate::Result<NightLightStatus> {
        let state = self.lock_state()?;
        let solar_status = current_solar_status(&state)?;
        let process = hyprsunset_process_state();
        Ok(NightLightStatus {
            mode: state.mode,
            running: process.running,
            temperature: process.temperature,
            target_temperature: target_temperature(&state),
            dark_hint: current_dark_hint()?,
            scheduled_running: solar_status.is_night,
            scheduled_dark_hint: solar_status.is_dark,
        })
    }

    fn reconcile_locked(
        &self,
        state: &mut MutexGuard<'_, State>,
    ) -> crate::Result<NightLightStatus> {
        let solar_status = current_solar_status(state)?;
        let desired = desired_state(state.mode, state.manual_temperature, &solar_status);
        apply_desired_state(&desired)?;
        if state.pending_dark_hint_enable {
            apply_dark_hint_if_needed(true)?;
            state.pending_dark_hint_enable = false;
        }

        let process = hyprsunset_process_state();
        Ok(NightLightStatus {
            mode: state.mode,
            running: process.running,
            temperature: process.temperature,
            target_temperature: target_temperature(state),
            dark_hint: current_dark_hint()?,
            scheduled_running: solar_status.is_night,
            scheduled_dark_hint: solar_status.is_dark,
        })
    }

    fn lock_state(&self) -> crate::Result<MutexGuard<'_, State>> {
        self.state
            .lock()
            .map_err(|_| io::Error::other("night-light state lock poisoned").into())
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

fn entered_dark_window(
    previous: Option<&solar::SolarStatus>,
    current: &solar::SolarStatus,
) -> bool {
    current.is_dark && !previous.is_some_and(|status| status.is_dark)
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

    fn sample_solar_status(is_night: bool, is_dark: bool) -> solar::SolarStatus {
        let now = chrono::Local::now();
        solar::SolarStatus {
            location: solar::Coordinates {
                latitude: solar::DEFAULT_LATITUDE,
                longitude: solar::DEFAULT_LONGITUDE,
            },
            sunrise: now,
            sunset: now,
            is_night,
            is_dark,
            next_sunrise: now,
            next_sunset: now,
            next_dark_on: now,
        }
    }

    #[test]
    fn desired_state_auto_tracks_solar_schedule() {
        let desired = desired_state(
            NightLightMode::Auto,
            5200,
            &sample_solar_status(true, false),
        );

        assert!(desired.running);
        assert_eq!(desired.temperature, solar::HYPRSUNSET_TEMP);
    }

    #[test]
    fn desired_state_manual_modes_use_manual_temperature() {
        let solar_status = sample_solar_status(false, true);

        let on = desired_state(NightLightMode::On, 5100, &solar_status);
        assert!(on.running);
        assert_eq!(on.temperature, 5100);

        let off = desired_state(NightLightMode::Off, 5100, &solar_status);
        assert!(!off.running);
        assert_eq!(off.temperature, 5100);
    }

    #[test]
    fn dark_hint_enable_only_triggers_on_dark_window_entry() {
        let previous = sample_solar_status(true, false);
        let current = sample_solar_status(true, true);

        assert!(entered_dark_window(Some(&previous), &current));
        assert!(entered_dark_window(None, &current));
        assert!(!entered_dark_window(Some(&current), &current));
        assert!(!entered_dark_window(Some(&current), &previous));
    }

    #[test]
    fn target_temperature_uses_schedule_only_in_auto_mode() {
        let auto = State {
            mode: NightLightMode::Auto,
            manual_temperature: 5100,
            solar_status: None,
            pending_dark_hint_enable: false,
        };
        let on = State {
            mode: NightLightMode::On,
            manual_temperature: 5100,
            solar_status: None,
            pending_dark_hint_enable: false,
        };

        assert_eq!(target_temperature(&auto), solar::HYPRSUNSET_TEMP);
        assert_eq!(target_temperature(&on), 5100);
    }
}
