//! Owns the session-restore state and records the running session.

use crate::{daemon::server::Events, session};
use futures_util::StreamExt;
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
use tokio::sync::watch;

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

/// Write the window list down whenever it changes, until logind announces a
/// shutdown: windows that close after that are the system going down, not the
/// user, and the list from just before must be the one that survives.
pub fn run(shutdown: Arc<AtomicBool>, halted: Arc<Mutex<bool>>) -> crate::Result<()> {
    let mut written = None;

    while !shutdown.load(Ordering::SeqCst) {
        thread::sleep(Duration::from_secs(1));
        let Ok(recording) = session::record() else {
            continue;
        };
        // Held across the write, so no look outlives the announcement.
        let halted = lock_halt(&halted)?;
        if *halted || written.as_ref() == Some(&recording) {
            continue;
        }
        session::persist_recording(&recording)?;
        written = Some(recording);
    }

    Ok(())
}

#[zbus::proxy(
    interface = "org.freedesktop.login1.Manager",
    default_service = "org.freedesktop.login1",
    default_path = "/org/freedesktop/login1"
)]
trait Login {
    fn inhibit(&self, what: &str, who: &str, why: &str, mode: &str) -> zbus::Result<zbus::OwnedFd>;

    #[zbus(signal)]
    fn prepare_for_shutdown(&self, start: bool) -> zbus::Result<()>;
}

/// Halt the recorder on logind's shutdown announcement, holding the shutdown
/// back with a delay lock until it has. Helium and Code close their windows on
/// the same announcement, so a fresh look then would already miss them.
pub async fn halt_on_shutdown(
    halted: Arc<Mutex<bool>>,
    mut shutdown: watch::Receiver<bool>,
) -> crate::Result<()> {
    let connection = zbus::Connection::system().await?;
    let login = LoginProxy::new(&connection).await?;
    let mut announcements = login.receive_prepare_for_shutdown().await?;
    let inhibit = || login.inhibit("shutdown", "desktopctl", "Recording the window session", "delay");
    let mut _delay = Some(inhibit().await?);

    loop {
        let start = tokio::select! {
            announcement = announcements.next() => match announcement {
                Some(announcement) => announcement.args()?.start,
                None => return Ok(()),
            },
            _ = shutdown.changed() => return Ok(()),
        };
        *lock_halt(&halted)? = start;
        // A cancelled shutdown resumes recording and needs the lock back.
        _delay = match start {
            true => None,
            false => Some(inhibit().await?),
        };
    }
}

fn lock_halt(halted: &Mutex<bool>) -> crate::Result<std::sync::MutexGuard<'_, bool>> {
    halted
        .lock()
        .map_err(|_| io::Error::other("session halt lock poisoned").into())
}
