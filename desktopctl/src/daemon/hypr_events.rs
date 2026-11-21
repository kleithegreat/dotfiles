//! Single async watcher for Hyprland's `.socket2.sock`, fanning connection and
//! line events out to daemon subscribers so multiple subsystems never hold
//! duplicate blocking sockets.

use crate::hypr;
use std::time::Duration;
use tokio::{
    io::{AsyncBufReadExt, BufReader},
    net::UnixStream,
    sync::{broadcast, watch},
};

const RETRY_DELAY: Duration = Duration::from_secs(2);
const CHANNEL_CAPACITY: usize = 256;

#[derive(Debug, Clone)]
pub enum HyprEvent {
    Connected,
    Line(String),
}

#[derive(Clone)]
pub struct HyprEvents {
    sender: broadcast::Sender<HyprEvent>,
}

impl HyprEvents {
    pub fn new() -> Self {
        let (sender, _) = broadcast::channel(CHANNEL_CAPACITY);
        Self { sender }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<HyprEvent> {
        self.sender.subscribe()
    }
}

pub async fn run(
    events: HyprEvents,
    mut shutdown: watch::Receiver<bool>,
    health: crate::daemon::SubsystemHealth,
) {
    loop {
        if *shutdown.borrow() {
            health.set_stopped("hypr-events");
            return;
        }

        let socket_path = match hypr::instance_socket(".socket2.sock") {
            Ok(path) => path,
            Err(error) => {
                health.set_degraded("hypr-events", error.to_string());
                if wait_retry(&mut shutdown).await {
                    health.set_stopped("hypr-events");
                    return;
                }
                continue;
            }
        };

        match UnixStream::connect(&socket_path).await {
            Ok(stream) => {
                health.set_running("hypr-events");
                let _ = events.sender.send(HyprEvent::Connected);
                let mut reader = BufReader::new(stream).lines();
                loop {
                    tokio::select! {
                        changed = shutdown.changed() => {
                            if changed.is_err() || *shutdown.borrow() {
                                health.set_stopped("hypr-events");
                                return;
                            }
                        }
                        line = reader.next_line() => match line {
                            Ok(Some(line)) => {
                                let _ = events.sender.send(HyprEvent::Line(line));
                            }
                            Ok(None) => {
                                health.set_degraded("hypr-events", "compositor closed event socket");
                                break;
                            }
                            Err(error) => {
                                health.set_degraded("hypr-events", format!("event socket read failed: {error}"));
                                break;
                            }
                        }
                    }
                }
            }
            Err(error) => {
                health.set_degraded(
                    "hypr-events",
                    format!("connect {}: {error}", socket_path.display()),
                );
            }
        }

        if wait_retry(&mut shutdown).await {
            health.set_stopped("hypr-events");
            return;
        }
    }
}

async fn wait_retry(shutdown: &mut watch::Receiver<bool>) -> bool {
    tokio::select! {
        changed = shutdown.changed() => changed.is_err() || *shutdown.borrow(),
        () = tokio::time::sleep(RETRY_DELAY) => false,
    }
}
