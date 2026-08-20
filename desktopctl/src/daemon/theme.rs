//! Serializes every theme mutation through one worker so applies never
//! interleave, without holding any lock across a multi-second apply. Requests
//! block until the apply completes — a reply means the state is durable —
//! and change events publish only after a successful commit.

use crate::{
    daemon::server::Events,
    theme::{self, ApplyScope, DarkHintOrigin},
};
use serde_json::Value;
use tokio::sync::{mpsc, oneshot};

#[derive(Debug)]
pub enum ThemeJob {
    Set {
        key: String,
        value: Value,
        origin: DarkHintOrigin,
    },
    Apply {
        scope: ApplyScope,
    },
    PresetApply {
        name: String,
    },
    PresetSave {
        name: String,
        payload: Value,
    },
    PresetDelete {
        name: String,
    },
}

struct ThemeRequest {
    job: ThemeJob,
    reply: oneshot::Sender<crate::Result<Value>>,
}

#[derive(Clone)]
pub struct ThemeController {
    sender: mpsc::UnboundedSender<ThemeRequest>,
}

impl ThemeController {
    pub fn spawn(events: Events) -> Self {
        let (sender, mut receiver) = mpsc::unbounded_channel::<ThemeRequest>();
        tokio::spawn(async move {
            while let Some(request) = receiver.recv().await {
                let events = events.clone();
                let result = match tokio::task::spawn_blocking(move || {
                    run_job(request.job, &events)
                })
                .await
                {
                    Ok(result) => result,
                    Err(error) => {
                        Err(std::io::Error::other(format!("theme job panicked: {error}")).into())
                    }
                };
                let _ = request.reply.send(result);
            }
        });

        Self { sender }
    }

    pub async fn request(&self, job: ThemeJob) -> crate::Result<Value> {
        let (reply, response) = oneshot::channel();
        self.sender
            .send(ThemeRequest { job, reply })
            .map_err(|_| std::io::Error::other("theme worker is gone"))?;
        response
            .await
            .map_err(|_| std::io::Error::other("theme worker dropped the reply"))?
    }

    /// For sync daemon code (the night-light reconcile thread).
    pub fn request_blocking(&self, job: ThemeJob) -> crate::Result<Value> {
        let (reply, response) = oneshot::channel();
        self.sender
            .send(ThemeRequest { job, reply })
            .map_err(|_| std::io::Error::other("theme worker is gone"))?;
        response
            .blocking_recv()
            .map_err(|_| std::io::Error::other("theme worker dropped the reply"))?
    }
}

fn run_job(job: ThemeJob, events: &Events) -> crate::Result<Value> {
    match job {
        ThemeJob::Set { key, value, origin } => {
            let outcome = theme::set_theme_key_core(&key, value, origin)?;
            let state = theme::state_json(&outcome.state);
            if outcome.changed {
                events.publish(
                    "theme.changed",
                    serde_json::json!({ "state": state, "changed_keys": [key] }),
                );
            }
            Ok(serde_json::json!({ "changed": outcome.changed, "state": state }))
        }
        ThemeJob::Apply { scope } => {
            let report = theme::apply_scope_core(&scope)?;
            Ok(report.to_json())
        }
        ThemeJob::PresetApply { name } => {
            let outcome = theme::apply_preset_core(&name)?;
            let state = theme::state_json(&outcome.state);
            if !outcome.changed_keys.is_empty() {
                events.publish(
                    "theme.changed",
                    serde_json::json!({ "state": state, "changed_keys": outcome.changed_keys }),
                );
            }
            Ok(serde_json::json!({ "state": state }))
        }
        ThemeJob::PresetSave { name, payload } => {
            let fields = theme::save_preset_core(&name, payload)?;
            publish_presets_changed(events);
            Ok(serde_json::json!({ "fields": fields }))
        }
        ThemeJob::PresetDelete { name } => {
            theme::delete_preset_core(&name)?;
            publish_presets_changed(events);
            Ok(serde_json::json!({}))
        }
    }
}

fn publish_presets_changed(events: &Events) {
    if let Ok(presets) = theme::preset_names() {
        events.publish(
            "theme.presets_changed",
            serde_json::json!({ "presets": presets }),
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{
        sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        },
        time::Duration,
    };

    // The worker must run jobs strictly one at a time even when requests
    // arrive concurrently. Two slow jobs submitted together may never be
    // observed in flight at once.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn worker_serializes_jobs() {
        let in_flight = Arc::new(AtomicUsize::new(0));
        let overlap_seen = Arc::new(AtomicUsize::new(0));

        // Exercise the queue shape directly rather than through run_job so
        // the test needs no theme state on disk.
        let (sender, mut receiver) = mpsc::unbounded_channel::<ThemeRequest>();
        let worker_in_flight = Arc::clone(&in_flight);
        let worker_overlap = Arc::clone(&overlap_seen);
        tokio::spawn(async move {
            while let Some(request) = receiver.recv().await {
                let in_flight = Arc::clone(&worker_in_flight);
                let overlap = Arc::clone(&worker_overlap);
                let result = tokio::task::spawn_blocking(move || {
                    if in_flight.fetch_add(1, Ordering::SeqCst) > 0 {
                        overlap.fetch_add(1, Ordering::SeqCst);
                    }
                    std::thread::sleep(Duration::from_millis(50));
                    in_flight.fetch_sub(1, Ordering::SeqCst);
                    Ok(serde_json::json!({}))
                })
                .await
                .expect("job task");
                let _ = request.reply.send(result);
            }
        });

        let mut replies = Vec::new();
        for _ in 0..3 {
            let (reply, response) = oneshot::channel();
            sender
                .send(ThemeRequest {
                    job: ThemeJob::Apply {
                        scope: ApplyScope::All,
                    },
                    reply,
                })
                .expect("send job");
            replies.push(response);
        }

        for response in replies {
            response.await.expect("worker reply").expect("job result");
        }
        assert_eq!(overlap_seen.load(Ordering::SeqCst), 0);
    }
}
