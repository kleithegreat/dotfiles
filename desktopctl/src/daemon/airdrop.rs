//! AirDrop's daemon half: one actor that holds owlyd's lease while anything
//! wants the radio, runs owly-airdrop's receiver while visible and its sender
//! while sharing, and publishes what the shell needs ([[airdrop]]). Commands
//! only change what is wanted; `reconcile` brings the radio to it, so a slow
//! acquire never blocks the socket.

use crate::{
    airdrop::{self, Ask, Receiver as Listed, Sending, Share, Status},
    daemon::server::Events,
};
use futures_util::StreamExt;
use owly_airdrop::{
    driver::{
        mdns::{Mdns, Registration},
        receiver::{Options, Receiver, ReceiverEvent, Request},
        sender::{self as send, Payload, Sender},
        tls::Identity,
    },
    proto::{
        ble::{APPLE_COMPANY_ID, Advert, INTERVAL_MS},
        mdns::{self, BrowseEvent, RECEIVER_FLAGS, SUPPORTS_DVZIP, Service},
        messages::Offer,
        receiver::Config as ReceiverConfig,
        sender::{Config as SenderConfig, Outcome},
    },
};
use serde_json::Value;
use std::{
    collections::{HashMap, HashSet},
    io,
    net::{Ipv6Addr, SocketAddrV6},
    path::PathBuf,
    sync::{Arc, Mutex},
    time::{Duration, SystemTime, UNIX_EPOCH},
};
use tokio::{
    sync::{mpsc, oneshot, watch},
    task::JoinHandle,
    time::Instant,
};
use zbus::{OwnedObjectPath, OwnedVariant, Variant};

/// Where we receive, and what the owly module opens on `awdl0`.
const RECEIVE_PORT: u16 = 8771;
/// Where Apple receivers listen, and where an AWDL peer without mDNS is tried.
const AIRDROP_PORT: u16 = 8770;
const ADVERT: &str = "/desktopctl/airdrop/advert";
const ADVERTISING: &str = "org.bluez.LEAdvertisingManager1";
const ADAPTER: &str = "org.bluez.Adapter1";
/// An AWDL peer that is silent must not hold up the rest of a round.
const KNOCK: Duration = Duration::from_secs(3);

#[zbus::proxy(
    interface = "io.github.t4t5.Owly.Radio1",
    default_service = "io.github.t4t5.Owly",
    default_path = "/io/github/t4t5/Owly"
)]
trait Radio {
    fn probe(&self) -> zbus::Result<String>;
    fn acquire(&self, duration: u32) -> zbus::Result<(u64, HashMap<String, OwnedVariant>)>;
    fn release(&self, lease: u64) -> zbus::Result<()>;
    #[zbus(signal, name = "StateChanged")]
    fn state_changed(&self, lease: u64, state: String, reason: String) -> zbus::Result<()>;
    #[zbus(property)]
    fn peers(&self) -> zbus::Result<Vec<HashMap<String, OwnedVariant>>>;
}

enum Command {
    Visible(bool),
    Answer { id: u64, accept: bool },
    Share(Outgoing),
    Send(String),
    Cancel,
}

type Reply = oneshot::Sender<Result<(), String>>;
type Inbox = mpsc::UnboundedReceiver<(Command, Reply)>;

#[derive(Clone)]
pub struct AirDropController {
    commands: mpsc::UnboundedSender<(Command, Reply)>,
    inbox: Arc<Mutex<Option<Inbox>>>,
    status: Arc<Mutex<Status>>,
    events: Events,
}

impl AirDropController {
    pub fn new(events: Events) -> Self {
        let (commands, inbox) = mpsc::unbounded_channel();
        Self {
            commands,
            inbox: Arc::new(Mutex::new(Some(inbox))),
            status: Arc::default(),
            events,
        }
    }

    pub fn status(&self) -> crate::Result<Value> {
        let status = self
            .status
            .lock()
            .map_err(|_| io::Error::other("airdrop lock poisoned"))?;
        Ok(serde_json::to_value(&*status)?)
    }

    pub async fn visible(&self, enabled: bool) -> crate::Result<Value> {
        self.command(Command::Visible(enabled)).await
    }

    pub async fn answer(&self, id: u64, accept: bool) -> crate::Result<Value> {
        self.command(Command::Answer { id, accept }).await
    }

    pub async fn share(
        &self,
        paths: Vec<PathBuf>,
        urls: Vec<String>,
        text: Option<String>,
    ) -> crate::Result<Value> {
        let outgoing = match (paths.is_empty(), urls.is_empty(), text) {
            (false, true, None) => Outgoing::files(paths),
            (true, false, None) => Outgoing::links(urls),
            (true, true, Some(text)) => Outgoing::text(&text)?,
            _ => {
                return Err(
                    crate::invalid_input("share files, links or text, one kind at a time").into(),
                );
            }
        };
        self.command(Command::Share(outgoing)).await
    }

    pub async fn send(&self, receiver: String) -> crate::Result<Value> {
        self.command(Command::Send(receiver)).await
    }

    pub async fn cancel(&self) -> crate::Result<Value> {
        self.command(Command::Cancel).await
    }

    async fn command(&self, command: Command) -> crate::Result<Value> {
        let (reply, answer) = oneshot::channel();
        self.commands
            .send((command, reply))
            .map_err(|_| io::Error::other("AirDrop is not running"))?;
        answer
            .await
            .map_err(|_| io::Error::other("AirDrop is not running"))?
            .map_err(io::Error::other)?;
        Ok(Value::Object(Default::default()))
    }
}

fn name_of(path: &std::path::Path) -> String {
    path.file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| path.display().to_string())
}

/// What a share offers, and what the shell shows of it.
struct Outgoing {
    payload: Payload,
    kind: &'static str,
    items: Vec<String>,
    preview: Option<PathBuf>,
    /// Holds the note that shared text travels as, for as long as it is offered.
    _note: Option<Scratch>,
}

impl Outgoing {
    fn files(paths: Vec<PathBuf>) -> Self {
        Self {
            kind: "files",
            items: paths.iter().map(|path| name_of(path)).collect(),
            preview: paths.first().cloned(),
            payload: Payload::Files(paths),
            _note: None,
        }
    }

    fn links(urls: Vec<String>) -> Self {
        Self {
            kind: "links",
            items: urls.clone(),
            preview: None,
            payload: Payload::Urls(urls),
            _note: None,
        }
    }

    /// Text that is one link goes as that link; anything else as a note.
    fn text(text: &str) -> io::Result<Self> {
        let text = text.trim();
        if text.is_empty() {
            return Err(crate::invalid_input("there is no text to share"));
        }
        if !text.contains(char::is_whitespace)
            && (text.starts_with("https://") || text.starts_with("http://"))
        {
            return Ok(Self::links(vec![text.to_owned()]));
        }
        let note = Scratch::new()?;
        let path = note.0.join(format!("{}.txt", note_title(text)));
        std::fs::write(&path, text)?;
        Ok(Self {
            payload: Payload::Files(vec![path]),
            kind: "text",
            items: vec![text.chars().take(600).collect()],
            preview: None,
            _note: Some(note),
        })
    }
}

/// A note's file name: its first words, as a phone shows it.
fn note_title(text: &str) -> String {
    let title: String = text
        .lines()
        .find(|line| !line.trim().is_empty())
        .unwrap_or_default()
        .chars()
        .filter(|c| !c.is_control() && *c != '/')
        .take(40)
        .collect();
    match title.trim() {
        "" => "Text".to_owned(),
        title => title.to_owned(),
    }
}

/// A directory of our own under the runtime dir, removed with this.
struct Scratch(PathBuf);

impl Scratch {
    fn new() -> io::Result<Self> {
        let bytes: [u8; 8] = random()?;
        let dir = crate::paths::xdg_runtime_dir()?
            .join("desktopctl/airdrop")
            .join(format!("{:016x}", u64::from_ne_bytes(bytes)));
        std::fs::create_dir_all(&dir)?;
        Ok(Self(dir))
    }

    /// Keeps an offer's thumbnail if it is a format the shell can draw.
    fn picture(&self, id: u64, bytes: &[u8]) -> Option<PathBuf> {
        let extension = match image::guess_format(bytes) {
            Ok(image::ImageFormat::Jpeg) => "jpg",
            Ok(image::ImageFormat::Png) => "png",
            _ => {
                let head: Vec<String> = bytes.iter().take(12).map(|b| format!("{b:02x}")).collect();
                tracing::warn!(head = %head.join(" "), "airdrop: offer thumbnail not drawable");
                return None;
            }
        };
        let path = self.0.join(format!("{id}.{extension}"));
        std::fs::write(&path, bytes).ok()?;
        Some(path)
    }
}

impl Drop for Scratch {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

enum Internal {
    Leased(Result<Lease, String>),
    Released,
    Receiver(Box<ReceiverEvent>),
    Listed(Found),
    Lost(String),
    Progress(send::Event),
    Sent(Result<Outcome, String>),
}

#[derive(Clone)]
struct Lease {
    id: u64,
    index: u32,
    address: Ipv6Addr,
    burst: Option<mdns::Burst>,
}

struct Found {
    id: String,
    name: String,
    addr: SocketAddrV6,
    flags: u32,
}

/// Aborts its tasks when dropped, so ending a session is dropping it.
#[derive(Default)]
struct Tasks(Vec<JoinHandle<()>>);

impl Drop for Tasks {
    fn drop(&mut self) {
        self.0.iter().for_each(JoinHandle::abort);
    }
}

struct Receiving {
    _service: Registration,
    icons: Scratch,
    _tasks: Tasks,
    /// Dropping one declines it.
    pending: HashMap<u64, Request>,
}

struct Sharing {
    sender: Arc<Sender>,
    payload: Payload,
    found: HashMap<String, (SocketAddrV6, u32)>,
    advert: Option<Advertising>,
    send_task: Option<JoinHandle<()>>,
    _tasks: Tasks,
}

impl Drop for Sharing {
    fn drop(&mut self) {
        if let Some(task) = self.send_task.take() {
            task.abort();
        }
    }
}

enum RadioState {
    Idle,
    Acquiring,
    Leased(Lease),
    /// The lease being given back, until owlyd says it is idle.
    Releasing(u64),
}

#[derive(Clone, Copy)]
struct VisibleDeadline {
    until: Instant,
    unix_secs: u64,
}

struct ActorState {
    internal: mpsc::UnboundedSender<Internal>,
    controller: AirDropController,
    status: Status,
    name: String,
    want_visible: Option<VisibleDeadline>,
    want_share: Option<Outgoing>,
    radio_state: RadioState,
    receiving: Option<Receiving>,
    sharing: Option<Sharing>,
}

struct Actor {
    conn: zbus::Connection,
    radio: RadioProxy<'static>,
    state: ActorState,
}

pub async fn run(
    controller: AirDropController,
    system_bus: Option<zbus::Connection>,
    mut shutdown: watch::Receiver<bool>,
    health: crate::daemon::SubsystemHealth,
) -> crate::Result<()> {
    let Some(conn) = system_bus else {
        health.set_degraded("airdrop", "system D-Bus unavailable");
        return Ok(());
    };
    let mut inbox = controller
        .inbox
        .lock()
        .map_err(|_| io::Error::other("airdrop lock poisoned"))?
        .take()
        .ok_or_else(|| io::Error::other("airdrop already running"))?;
    // owly-airdrop leaves rustls's provider to its caller.
    let _ = rustls::crypto::ring::default_provider().install_default();
    let radio = RadioProxy::builder(&conn)
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await?;
    let mut states = radio.receive_state_changed().await?;
    let (internal, mut internals) = mpsc::unbounded_channel();
    let mode = probe(&radio).await;
    if mode.is_some() {
        health.set_running("airdrop");
    } else {
        health.set_degraded("airdrop", "owlyd unavailable or no usable AirDrop radio");
    }
    let mut actor = Actor {
        conn,
        radio,
        state: ActorState::new(internal, controller, hostname(), mode),
    };
    actor.state.publish();

    loop {
        let deadline = actor.state.want_visible.map(|visible| visible.until);
        tokio::select! {
            Some((command, reply)) = inbox.recv() => {
                let _ = reply.send(actor.state.command(command));
            }
            Some(event) = internals.recv() => actor.state.internal(event),
            Some(signal) = states.next() => {
                if let Ok(args) = signal.args() {
                    actor.state.radio_state(args.lease, &args.state, &args.reason);
                }
            }
            () = tokio::time::sleep_until(deadline.unwrap_or_else(Instant::now)), if deadline.is_some() => {
                actor.state.want_visible = None;
            }
            // owlyd ends a lease whose owner leaves the bus, so exiting gives the radio back.
            _ = shutdown.changed() => {
                actor.shutdown().await;
                health.set_stopped("airdrop");
                return Ok(());
            }
        }
        actor.reconcile().await;
        actor.state.publish();
    }
}

/// How the radio runs here, or `None` when AirDrop cannot use it.
async fn probe(radio: &RadioProxy<'_>) -> Option<String> {
    let report: Value = match radio.probe().await {
        Ok(report) => serde_json::from_str(&report).ok()?,
        Err(error) => {
            tracing::warn!(error = %error, "airdrop: owlyd unreachable");
            return None;
        }
    };
    let missing = report["missing"]
        .as_array()
        .is_some_and(|missing| !missing.is_empty());
    match missing {
        true => None,
        false => report["mode"].as_str().map(str::to_owned),
    }
}

fn hostname() -> String {
    let mut buffer = [0u8; 256];
    let length = match unsafe { libc::gethostname(buffer.as_mut_ptr().cast(), buffer.len()) } {
        0 => buffer
            .iter()
            .position(|&byte| byte == 0)
            .unwrap_or(buffer.len()),
        _ => 0,
    };
    match String::from_utf8_lossy(&buffer[..length]).into_owned() {
        name if name.is_empty() => "Linux".to_owned(),
        name => name,
    }
}

impl ActorState {
    fn new(
        internal: mpsc::UnboundedSender<Internal>,
        controller: AirDropController,
        name: String,
        mode: Option<String>,
    ) -> Self {
        Self {
            internal,
            controller,
            status: Status {
                mode,
                ..Status::default()
            },
            name,
            want_visible: None,
            want_share: None,
            radio_state: RadioState::Idle,
            receiving: None,
            sharing: None,
        }
    }

    fn command(&mut self, command: Command) -> Result<(), String> {
        match command {
            Command::Visible(true) => {
                self.status
                    .mode
                    .as_ref()
                    .ok_or("AirDrop has no radio it can use here")?;
                let until = Instant::now() + airdrop::VISIBLE_FOR;
                let unix_secs = (SystemTime::now() + airdrop::VISIBLE_FOR)
                    .duration_since(UNIX_EPOCH)
                    .map_or(0, |since| since.as_secs());
                self.want_visible = Some(VisibleDeadline { until, unix_secs });
            }
            Command::Visible(false) => self.want_visible = None,
            Command::Answer { id, accept } => {
                let receiving = self.receiving.as_mut().ok_or("that request is gone")?;
                let request = receiving
                    .pending
                    .remove(&id)
                    .ok_or("that request is gone")?;
                match accept {
                    true => {
                        request.accept();
                        self.status
                            .requests
                            .iter_mut()
                            .filter(|ask| ask.id == id)
                            .for_each(|ask| ask.accepted = true);
                    }
                    false => {
                        request.decline();
                        self.status.requests.retain(|ask| ask.id != id);
                    }
                }
            }
            Command::Share(outgoing) => {
                self.status
                    .mode
                    .as_ref()
                    .ok_or("AirDrop has no radio it can use here")?;
                self.stop_sharing();
                self.status.share = Some(Share {
                    kind: outgoing.kind.to_owned(),
                    items: outgoing.items.clone(),
                    preview: outgoing.preview.clone(),
                    receivers: Vec::new(),
                    sending: None,
                });
                self.want_share = Some(outgoing);
            }
            Command::Send(id) => {
                let sharing = self.sharing.as_mut().ok_or("nothing is being shared")?;
                let share = self
                    .status
                    .share
                    .as_mut()
                    .ok_or("nothing is being shared")?;
                if sharing.send_task.is_some()
                    || share
                        .sending
                        .as_ref()
                        .is_some_and(|s| matches!(s.state.as_str(), "asking" | "sending"))
                {
                    return Err("a send is already in progress".to_owned());
                }
                let &(addr, flags) = sharing.found.get(&id).ok_or("that receiver is gone")?;
                let to = share
                    .receivers
                    .iter()
                    .find(|receiver| receiver.id == id)
                    .map(|receiver| receiver.name.clone())
                    .unwrap_or_default();
                share.sending = Some(Sending {
                    to,
                    state: "asking".to_owned(),
                    sent: 0,
                    total: 0,
                    error: None,
                });
                sharing.send_task = Some(send_to(
                    sharing.sender.clone(),
                    sharing.payload.clone(),
                    addr,
                    flags,
                    self.internal.clone(),
                ));
            }
            Command::Cancel => {
                self.want_share = None;
                self.status.share = None;
            }
        }
        Ok(())
    }

    fn internal(&mut self, event: Internal) {
        match event {
            Internal::Leased(result) => {
                if matches!(self.radio_state, RadioState::Acquiring) {
                    match result {
                        Ok(lease) => self.radio_state = RadioState::Leased(lease),
                        Err(error) => {
                            self.radio_state = RadioState::Idle;
                            self.give_up(&error);
                        }
                    }
                }
            }
            Internal::Released => {
                if matches!(self.radio_state, RadioState::Releasing(_)) {
                    self.radio_state = RadioState::Idle;
                }
            }
            Internal::Receiver(event) => self.received(*event),
            Internal::Listed(found) => {
                let (Some(sharing), Some(share)) = (&mut self.sharing, &mut self.status.share)
                else {
                    return;
                };
                sharing
                    .found
                    .insert(found.id.clone(), (found.addr, found.flags));
                share.receivers.retain(|receiver| receiver.id != found.id);
                share.receivers.push(Listed {
                    id: found.id,
                    name: found.name,
                });
            }
            Internal::Lost(id) => {
                if let (Some(sharing), Some(share)) = (&mut self.sharing, &mut self.status.share) {
                    sharing.found.remove(&id);
                    share.receivers.retain(|receiver| receiver.id != id);
                }
            }
            Internal::Progress(progress) => {
                let Some(sending) = self
                    .status
                    .share
                    .as_mut()
                    .and_then(|share| share.sending.as_mut())
                else {
                    return;
                };
                sending.state = "sending".to_owned();
                if let send::Event::Progress(progress) = progress {
                    sending.sent = progress.sent;
                    sending.total = progress.total;
                }
            }
            Internal::Sent(outcome) => {
                if let Some(sharing) = &mut self.sharing {
                    sharing.send_task = None;
                }
                let Some(sending) = self
                    .status
                    .share
                    .as_mut()
                    .and_then(|share| share.sending.as_mut())
                else {
                    return;
                };
                let (state_str, err) = match outcome {
                    Ok(Outcome::Delivered) => ("sent", None),
                    Ok(Outcome::Declined) => ("declined", None),
                    Ok(Outcome::Failed(reason)) | Err(reason) => ("failed", Some(reason)),
                };
                sending.state = state_str.to_owned();
                sending.error = err;
            }
        }
    }

    fn received(&mut self, event: ReceiverEvent) {
        let Some(receiving) = &mut self.receiving else {
            return;
        };
        let finished = |status: &mut Status, id: u64| {
            let sender = status
                .requests
                .iter()
                .find(|ask| ask.id == id)
                .map(|ask| ask.sender.clone());
            status.requests.retain(|ask| ask.id != id);
            sender.unwrap_or_default()
        };
        match event {
            ReceiverEvent::Discovered { .. } => {}
            ReceiverEvent::Request(request) => {
                let (files, urls) = match &request.ask.offer {
                    Offer::Files(files) => (
                        files.iter().map(|file| file.name.clone()).collect(),
                        Vec::new(),
                    ),
                    Offer::Urls(urls) => (Vec::new(), urls.clone()),
                };
                self.status.requests.push(Ask {
                    id: request.id,
                    sender: request.ask.sender_computer_name.clone(),
                    files,
                    urls,
                    icon: request
                        .ask
                        .file_icon
                        .as_deref()
                        .and_then(|bytes| receiving.icons.picture(request.id, bytes)),
                    accepted: false,
                });
                receiving.pending.insert(request.id, request);
            }
            ReceiverEvent::Withdrawn { id } => {
                receiving.pending.remove(&id);
                finished(&mut self.status, id);
            }
            ReceiverEvent::Urls { id, urls } => {
                let sender = finished(&mut self.status, id);
                self.controller.events.publish(
                    "airdrop.received",
                    serde_json::json!({ "sender": sender, "paths": [], "urls": urls }),
                );
            }
            ReceiverEvent::Received { id, paths } => {
                let sender = finished(&mut self.status, id);
                self.controller.events.publish(
                    "airdrop.received",
                    serde_json::json!({ "sender": sender, "paths": paths, "urls": [] }),
                );
            }
            ReceiverEvent::Failed { id, reason } => {
                let sender = finished(&mut self.status, id);
                self.controller.events.publish(
                    "airdrop.failed",
                    serde_json::json!({ "reason": format!("From {sender}: {reason}") }),
                );
            }
        }
    }

    fn radio_state(&mut self, lease: u64, state: &str, reason: &str) {
        if state != "idle" {
            return;
        }
        match &self.radio_state {
            RadioState::Releasing(id) if *id == lease => self.radio_state = RadioState::Idle,
            RadioState::Leased(ours) if ours.id == lease => {
                self.radio_state = RadioState::Idle;
                self.give_up(reason);
            }
            _ => {}
        }
    }

    /// The radio is not coming, or went: everything that wanted it stops.
    fn give_up(&mut self, reason: &str) {
        self.want_visible = None;
        self.want_share = None;
        self.status.share = None;
        self.controller
            .events
            .publish("airdrop.failed", serde_json::json!({ "reason": reason }));
    }

    fn stop_sharing(&mut self) {
        if let Some(mut sharing) = self.sharing.take()
            && let Some(advert) = sharing.advert.take()
        {
            tokio::spawn(advert.stop());
        }
    }

    fn publish(&self) {
        let mut status = self.status.clone();
        status.busy = matches!(
            self.radio_state,
            RadioState::Acquiring | RadioState::Releasing(_)
        );
        status.visible_until = self.want_visible.map(|visible| visible.unix_secs);
        let Ok(mut shared) = self.controller.status.lock() else {
            return;
        };
        if *shared != status {
            let value = serde_json::to_value(&status).unwrap_or_default();
            *shared = status;
            self.controller.events.publish("airdrop.changed", value);
        }
    }
}

impl Actor {
    async fn reconcile(&mut self) {
        let wanted = self.state.want_visible.is_some() || self.state.want_share.is_some();
        if self.state.want_visible.is_none() {
            self.state.receiving = None;
            self.state.status.requests.clear();
        }
        if self.state.want_share.is_none() {
            self.state.stop_sharing();
        }

        let lease = match &self.state.radio_state {
            RadioState::Idle if wanted => {
                self.state.radio_state = RadioState::Acquiring;
                tokio::spawn(acquire(self.radio.clone(), self.state.internal.clone()));
                return;
            }
            RadioState::Leased(lease) if !wanted => {
                let id = lease.id;
                self.state.radio_state = RadioState::Releasing(id);
                tokio::spawn(release(self.radio.clone(), id, self.state.internal.clone()));
                return;
            }
            RadioState::Leased(lease) => lease.clone(),
            RadioState::Idle | RadioState::Acquiring | RadioState::Releasing(_) => return,
        };

        if self.state.want_visible.is_some() && self.state.receiving.is_none() {
            match self.start_receiving(&lease).await {
                Ok(receiving) => self.state.receiving = Some(receiving),
                Err(error) => {
                    self.state.want_visible = None;
                    self.state.give_up(&format!("Receiving failed: {error}"));
                }
            }
        }
        if self.state.sharing.is_none()
            && let Some(payload) = self
                .state
                .want_share
                .as_ref()
                .map(|outgoing| outgoing.payload.clone())
        {
            match self.start_sharing(&lease, payload).await {
                Ok(sharing) => self.state.sharing = Some(sharing),
                Err(error) => self.state.give_up(&format!("Sharing failed: {error}")),
            }
        }
    }

    async fn shutdown(&mut self) {
        self.state.receiving = None;
        if let Some(mut sharing) = self.state.sharing.take()
            && let Some(advert) = sharing.advert.take()
        {
            advert.stop().await;
        }
    }

    async fn start_receiving(&self, lease: &Lease) -> io::Result<Receiving> {
        let identity = Identity::load_or_generate(&identity_dir()?)?;
        let destination = airdrop::downloads().map_err(io::Error::other)?;
        let addr = SocketAddrV6::new(lease.address, RECEIVE_PORT, 0, lease.index);
        let options = Options::new(ReceiverConfig::new(self.state.name.clone()), destination);
        let (receiver, mut events) = Receiver::bind(addr, &identity, options).await?;
        let instance = service_id()?;
        let service = Service {
            host: format!("desktopctl-{instance}"),
            instance,
            port: RECEIVE_PORT,
            addr: lease.address,
            flags: RECEIVER_FLAGS,
        };
        let registration = Mdns::new(lease.index)
            .with_burst(lease.burst)
            .register(service)
            .await?;
        let internal = self.state.internal.clone();
        let forward = tokio::spawn(async move {
            while let Some(event) = events.recv().await {
                if internal.send(Internal::Receiver(Box::new(event))).is_err() {
                    return;
                }
            }
        });
        Ok(Receiving {
            _service: registration,
            icons: Scratch::new()?,
            _tasks: Tasks(vec![tokio::spawn(receiver.run()), forward]),
            pending: HashMap::new(),
        })
    }

    /// Receivers come two ways: mDNS, and `/Discover` at each AWDL peer,
    /// since an iPhone's mDNS does not reach `awdl0`.
    async fn start_sharing(&self, lease: &Lease, payload: Payload) -> io::Result<Sharing> {
        let sender = Arc::new(Sender::new(SenderConfig::new(
            self.state.name.clone(),
            service_id()?,
        ))?);
        let advert = Advertising::start(&self.conn)
            .await
            .inspect_err(|error| {
                tracing::warn!(
                    error = %error,
                    "airdrop: no BLE advert, so asleep iPhones stay asleep"
                )
            })
            .ok();
        let mut browse = Mdns::new(lease.index).browse().await?;
        let index = lease.index;

        let by_mdns = tokio::spawn({
            let (sender, internal) = (sender.clone(), self.state.internal.clone());
            async move {
                while let Some(event) = browse.events.recv().await {
                    let event = match event {
                        BrowseEvent::Found(found) => {
                            let addr = SocketAddrV6::new(found.addr, found.port, 0, index);
                            match sender.discover(addr).await {
                                Ok(Some(receiver)) => Internal::Listed(Found {
                                    id: found.instance,
                                    name: receiver.computer_name,
                                    addr,
                                    flags: found.flags,
                                }),
                                _ => continue,
                            }
                        }
                        BrowseEvent::Lost(instance) => Internal::Lost(instance),
                    };
                    if internal.send(event).is_err() {
                        return;
                    }
                }
            }
        });
        let by_peers = tokio::spawn({
            let (sender, internal, radio) = (
                sender.clone(),
                self.state.internal.clone(),
                self.radio.clone(),
            );
            async move {
                let mut seen: HashSet<String> = HashSet::new();
                loop {
                    let current: HashSet<String> = peers(&radio).await.into_iter().collect();
                    let lost: Vec<String> = seen.difference(&current).cloned().collect();
                    for gone in lost {
                        seen.remove(&gone);
                        if internal.send(Internal::Lost(gone)).is_err() {
                            return;
                        }
                    }
                    for mac in current {
                        let Some(address) = airdrop::link_local(&mac) else {
                            continue;
                        };
                        let addr = SocketAddrV6::new(address, AIRDROP_PORT, 0, index);
                        let Ok(Ok(Some(receiver))) =
                            tokio::time::timeout(KNOCK, sender.discover(addr)).await
                        else {
                            continue;
                        };
                        seen.insert(mac.clone());
                        let found = Found {
                            id: mac,
                            name: receiver.computer_name,
                            addr,
                            // No TXT to say, and Apple receivers take DVZip.
                            flags: RECEIVER_FLAGS | SUPPORTS_DVZIP,
                        };
                        if internal.send(Internal::Listed(found)).is_err() {
                            return;
                        }
                    }
                    tokio::time::sleep(KNOCK).await;
                }
            }
        });
        Ok(Sharing {
            sender,
            payload,
            found: HashMap::new(),
            advert,
            send_task: None,
            _tasks: Tasks(vec![by_mdns, by_peers]),
        })
    }
}

async fn acquire(radio: RadioProxy<'static>, internal: mpsc::UnboundedSender<Internal>) {
    let result = match radio.acquire(0).await {
        Ok((id, link)) => {
            lease(id, &link).ok_or_else(|| "owlyd lent a link it did not describe".to_owned())
        }
        Err(zbus::Error::MethodError(_, Some(message), _)) => Err(message),
        Err(error) => Err(error.to_string()),
    };
    let _ = internal.send(Internal::Leased(result));
}

async fn release(radio: RadioProxy<'static>, id: u64, internal: mpsc::UnboundedSender<Internal>) {
    if let Err(error) = radio.release(id).await {
        tracing::warn!(error = %error, "airdrop: releasing the radio failed");
    }
    let _ = internal.send(Internal::Released);
}

/// owlyd's link dictionary: `index`, `address` and, when receivers on it
/// announce in bursts, `announce` as copies, µs between them, µs between bursts.
fn lease(id: u64, link: &HashMap<String, OwnedVariant>) -> Option<Lease> {
    let index = link.get("index")?.downcast_ref::<u32>().ok()?;
    let address = link
        .get("address")?
        .downcast_ref::<String>()
        .ok()?
        .parse()
        .ok()?;
    let burst = link
        .get("announce")
        .and_then(|value| <(u32, u32, u32)>::try_from(value.try_clone().ok()?).ok())
        .map(|(count, interval, pause)| mdns::Burst {
            count,
            interval: Duration::from_micros(interval.into()),
            pause: Duration::from_micros(pause.into()),
        });
    Some(Lease {
        id,
        index,
        address,
        burst,
    })
}

async fn peers(radio: &RadioProxy<'_>) -> Vec<String> {
    radio
        .peers()
        .await
        .unwrap_or_default()
        .iter()
        .filter_map(|peer| peer.get("mac")?.downcast_ref::<String>().ok())
        .collect()
}

fn send_to(
    sender: Arc<Sender>,
    payload: Payload,
    addr: SocketAddrV6,
    flags: u32,
    internal: mpsc::UnboundedSender<Internal>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let (events, mut progress) = mpsc::unbounded_channel();
        let forward = {
            let internal = internal.clone();
            tokio::spawn(async move {
                while let Some(event) = progress.recv().await {
                    let _ = internal.send(Internal::Progress(event));
                }
            })
        };
        let outcome = sender.send(addr, &payload, flags, Some(events)).await;
        let _ = forward.await;
        let _ = internal.send(Internal::Sent(outcome.map_err(|error| error.to_string())));
    })
}

/// The same identity `owly receive` uses, so a phone sees one receiver.
fn identity_dir() -> io::Result<PathBuf> {
    let state = match std::env::var_os("XDG_STATE_HOME") {
        Some(dir) if !dir.is_empty() => PathBuf::from(dir),
        _ => crate::paths::home_dir()?.join(".local/state"),
    };
    Ok(state.join("owly"))
}

fn random<const N: usize>() -> io::Result<[u8; N]> {
    let mut bytes = [0; N];
    getrandom::fill(&mut bytes).map_err(|error| io::Error::other(error.to_string()))?;
    Ok(bytes)
}

fn service_id() -> io::Result<String> {
    Ok(mdns::service_id(random()?))
}

/// The BLE advert that wakes Apple receivers so they open their port.
/// Bluetooth is turned on for it if it was off, and back off after.
struct Advertising {
    conn: zbus::Connection,
    adapter: OwnedObjectPath,
    powered_on: bool,
}

struct Advertisement(Vec<u8>);

#[zbus::interface(name = "org.bluez.LEAdvertisement1")]
impl Advertisement {
    fn release(&self) {}

    #[zbus(property, name = "Type")]
    fn kind(&self) -> &str {
        "peripheral"
    }

    #[zbus(property)]
    fn min_interval(&self) -> u32 {
        INTERVAL_MS
    }

    #[zbus(property)]
    fn max_interval(&self) -> u32 {
        INTERVAL_MS
    }

    #[zbus(property)]
    fn manufacturer_data(&self) -> HashMap<u16, Variant<'_>> {
        HashMap::from([(APPLE_COMPANY_ID, Variant::from(self.0.clone()))])
    }
}

#[zbus::proxy(interface = "org.bluez.Adapter1", default_service = "org.bluez")]
trait Adapter {
    #[zbus(property)]
    fn powered(&self) -> zbus::Result<bool>;
    #[zbus(property)]
    fn set_powered(&self, powered: bool) -> zbus::Result<()>;
}

#[zbus::proxy(
    interface = "org.bluez.LEAdvertisingManager1",
    default_service = "org.bluez"
)]
trait AdvertisingManager {
    fn register_advertisement(
        &self,
        advertisement: &zbus::ObjectPath<'_>,
        options: HashMap<&str, Variant<'_>>,
    ) -> zbus::Result<()>;
    fn unregister_advertisement(&self, advertisement: &zbus::ObjectPath<'_>) -> zbus::Result<()>;
}

impl Advertising {
    async fn start(conn: &zbus::Connection) -> io::Result<Self> {
        let objects = zbus::fdo::ObjectManagerProxy::builder(conn)
            .destination("org.bluez")
            .path("/")
            .build()
            .await
            .map_err(io::Error::other)?
            .get_managed_objects()
            .await
            .map_err(io::Error::other)?;
        let adapter = objects
            .into_iter()
            .find(|(_, interfaces)| {
                let has = |wanted: &str| interfaces.keys().any(|name| name.as_str() == wanted);
                has(ADAPTER) && has(ADVERTISING)
            })
            .map(|(path, _)| path)
            .ok_or_else(|| io::Error::other("no adapter can advertise"))?;
        let power = AdapterProxy::builder(conn)
            .path(adapter.clone())
            .cache_properties(zbus::proxy::CacheProperties::No)
            .build()
            .await
            .map_err(io::Error::other)?;
        let powered_on = !power.powered().await.map_err(io::Error::other)?;
        if powered_on {
            power.set_powered(true).await.map_err(io::Error::other)?;
        }
        let advertising = Advertising {
            conn: conn.clone(),
            adapter,
            powered_on,
        };
        let data = Advert::anonymous(random()?).manufacturer_data();
        let registered = async {
            conn.object_server().at(ADVERT, Advertisement(data)).await?;
            advertising
                .manager()
                .await?
                .register_advertisement(&zbus::ObjectPath::try_from(ADVERT)?, HashMap::new())
                .await
        }
        .await;
        match registered {
            Ok(()) => Ok(advertising),
            Err(error) => {
                advertising.stop().await;
                Err(io::Error::other(error))
            }
        }
    }

    async fn manager(&self) -> zbus::Result<AdvertisingManagerProxy<'static>> {
        AdvertisingManagerProxy::builder(&self.conn)
            .path(self.adapter.clone())
            .build()
            .await
    }

    async fn stop(self) {
        if let Ok(manager) = self.manager().await
            && let Ok(path) = zbus::ObjectPath::try_from(ADVERT)
        {
            let _ = manager.unregister_advertisement(&path).await;
        }
        let _ = self
            .conn
            .object_server()
            .remove::<Advertisement, _>(ADVERT)
            .await;
        if self.powered_on
            && let Ok(power) = AdapterProxy::builder(&self.conn)
                .path(self.adapter.clone())
                .build()
                .await
        {
            let _ = power.set_powered(false).await;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn state_with_events(
        mode: Option<&str>,
    ) -> (
        ActorState,
        mpsc::UnboundedReceiver<Internal>,
        tokio::sync::broadcast::Receiver<Arc<crate::ipc::EventEnvelope>>,
    ) {
        let events = Events::new();
        let rx = events.receiver();
        let controller = AirDropController::new(events);
        let (internal_tx, internal_rx) = mpsc::unbounded_channel();
        (
            ActorState::new(
                internal_tx,
                controller,
                "test-host".to_owned(),
                mode.map(str::to_owned),
            ),
            internal_rx,
            rx,
        )
    }

    fn dummy_lease(id: u64) -> Lease {
        Lease {
            id,
            index: 1,
            address: Ipv6Addr::LOCALHOST,
            burst: None,
        }
    }

    #[test]
    fn text_that_is_one_link_goes_as_that_link() {
        let outgoing = Outgoing::text("  https://example.com/a?b=c \n").expect("link");
        assert_eq!(outgoing.kind, "links");
        assert_eq!(outgoing.items, ["https://example.com/a?b=c"]);
    }

    #[test]
    fn a_note_is_named_after_its_first_line() {
        assert_eq!(note_title("\n  Groceries / list\nmilk"), "Groceries  list");
        assert_eq!(note_title(&"x".repeat(60)), "x".repeat(40));
        assert_eq!(note_title(" \u{7}"), "Text");
    }

    #[test]
    fn radio_state_transitions_and_unexpected_idle_publish_failure() {
        let (mut state, _rx, _events) = state_with_events(None);
        assert!(state.command(Command::Visible(true)).is_err());

        let (mut state, _rx, mut events2) = state_with_events(Some("awdl0"));
        state
            .command(Command::Visible(true))
            .expect("visible enabled");
        assert!(state.want_visible.is_some());
        state.publish();
        assert!(state.controller.status().expect("status")["visible_until"].is_u64());

        state.radio_state = RadioState::Acquiring;
        state.publish();
        assert_eq!(state.controller.status().expect("status")["busy"], true);
        state.internal(Internal::Leased(Ok(dummy_lease(7))));
        assert!(matches!(state.radio_state, RadioState::Leased(ref l) if l.id == 7));
        state.publish();
        assert_eq!(state.controller.status().expect("status")["busy"], false);

        // Unrelated lease or non-idle signal does not abort the active lease.
        state.radio_state(7, "active", "");
        state.radio_state(99, "idle", "stale");
        assert!(state.want_visible.is_some());

        // Unexpected idle on the active lease stops everything and emits airdrop.failed.
        state.want_share = Some(Outgoing::links(vec!["https://example.com".to_owned()]));
        state
            .command(Command::Share(Outgoing::links(vec![
                "https://example.com".to_owned(),
            ])))
            .expect("share");
        state.radio_state(7, "idle", "wifi off");
        assert!(matches!(state.radio_state, RadioState::Idle));
        assert!(state.want_visible.is_none());
        assert!(state.want_share.is_none());
        assert!(state.status.share.is_none());

        let mut saw_failed = false;
        while let Ok(event) = events2.try_recv() {
            if event.event == "airdrop.failed" {
                saw_failed = event.data["reason"] == "wifi off";
            }
        }
        assert!(saw_failed);

        // Voluntary release does not emit airdrop.failed.
        state.radio_state = RadioState::Releasing(8);
        state.radio_state(8, "idle", "released");
        assert!(matches!(state.radio_state, RadioState::Idle));
        while let Ok(event) = events2.try_recv() {
            assert_ne!(event.event, "airdrop.failed");
        }
    }

    #[tokio::test]
    async fn sharing_tracks_peers_rejects_concurrent_send_and_resets_on_new_share() {
        let _ = rustls::crypto::ring::default_provider().install_default();
        let (mut state, _rx, _events) = state_with_events(Some("awdl0"));
        let outgoing = Outgoing::links(vec!["https://example.com".to_owned()]);
        state.command(Command::Share(outgoing)).expect("share");

        let sender = Arc::new(
            Sender::new(SenderConfig::new(
                "test".to_owned(),
                "0123456789abcdef".to_owned(),
            ))
            .expect("sender"),
        );
        state.sharing = Some(Sharing {
            sender,
            payload: Payload::Urls(vec!["https://example.com".to_owned()]),
            found: HashMap::new(),
            advert: None,
            send_task: None,
            _tasks: Tasks::default(),
        });

        let addr = SocketAddrV6::new(Ipv6Addr::LOCALHOST, AIRDROP_PORT, 0, 1);
        state.internal(Internal::Listed(Found {
            id: "peer1".to_owned(),
            name: "iPhone".to_owned(),
            addr,
            flags: 0,
        }));
        assert_eq!(
            state.status.share.as_ref().expect("share").receivers.len(),
            1
        );

        state
            .command(Command::Send("peer1".to_owned()))
            .expect("send starts");
        assert_eq!(
            state
                .status
                .share
                .as_ref()
                .and_then(|s| s.sending.as_ref())
                .map(|s| s.state.as_str()),
            Some("asking")
        );
        assert!(state.command(Command::Send("peer1".to_owned())).is_err());

        state.internal(Internal::Sent(Ok(Outcome::Declined)));
        assert_eq!(
            state
                .status
                .share
                .as_ref()
                .and_then(|s| s.sending.as_ref())
                .map(|s| s.state.as_str()),
            Some("declined")
        );

        state.internal(Internal::Lost("peer1".to_owned()));
        assert!(
            state
                .status
                .share
                .as_ref()
                .expect("share")
                .receivers
                .is_empty()
        );

        // Starting a new share drops prior active sharing and clears receivers/sending state.
        state
            .command(Command::Share(Outgoing::links(vec![
                "https://example.org".to_owned(),
            ])))
            .expect("replace share");
        assert!(state.sharing.is_none());
        assert_eq!(
            state.status.share.as_ref().expect("new share").items,
            vec!["https://example.org".to_owned()]
        );

        state.command(Command::Cancel).expect("cancel share");
        assert!(state.want_share.is_none());
        assert!(state.status.share.is_none());
    }
}
