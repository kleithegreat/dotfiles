//! Owns the session-restore state and records the running session.

use crate::{daemon::server::Events, session};
use serde_json::Value;
use std::{
    io, mem,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::Duration,
};

/// Seconds between looks at the window list.
const RECORD_INTERVAL: u32 = 10;

#[derive(Clone)]
pub struct SessionController {
    state: Arc<Mutex<session::State>>,
    events: Events,
}

impl SessionController {
    pub fn new(state: session::State, events: Events) -> Self {
        Self {
            state: Arc::new(Mutex::new(state)),
            events,
        }
    }

    pub fn status(&self) -> crate::Result<Value> {
        Ok(self.lock()?.status())
    }

    pub fn set_automatic(&self, automatic: bool) -> crate::Result<Value> {
        let mut state = self.lock()?;
        state.automatic = automatic;
        self.commit(&state)
    }

    /// Restoring consumes the saved windows, so a second request finds nothing
    /// to duplicate.
    pub fn restore(&self, if_automatic: bool) -> crate::Result<Value> {
        let (windows, status) = {
            let mut state = self.lock()?;
            if if_automatic && !state.automatic {
                return Ok(state.status());
            }
            let windows = mem::take(&mut state.last);
            (windows, self.commit(&state)?)
        };
        session::restore(&windows)?;
        Ok(status)
    }

    fn commit(&self, state: &session::State) -> crate::Result<Value> {
        state.persist()?;
        let status = state.status();
        self.events.publish("session.changed", status.clone());
        Ok(status)
    }

    fn lock(&self) -> crate::Result<std::sync::MutexGuard<'_, session::State>> {
        self.state
            .lock()
            .map_err(|_| io::Error::other("session controller lock poisoned").into())
    }
}

/// Write the window list down once two consecutive looks agree on it. A
/// session shutting down closes its windows moments before this process is
/// stopped, and a list that is still changing must never replace the one that
/// was true while the session was whole.
pub fn run(shutdown: Arc<AtomicBool>) -> crate::Result<()> {
    let mut seen = None;
    let mut written = None;
    let mut tick = 0;

    while !shutdown.load(Ordering::SeqCst) {
        thread::sleep(Duration::from_secs(1));
        tick += 1;
        if tick % RECORD_INTERVAL != 0 {
            continue;
        }

        let recording = session::record().ok();
        if shutdown.load(Ordering::SeqCst) {
            break;
        }
        if recording.is_some() && recording == seen && recording != written {
            if let Some(recording) = &recording {
                session::persist_recording(recording)?;
            }
            written = recording.clone();
        }
        seen = recording;
    }

    Ok(())
}
