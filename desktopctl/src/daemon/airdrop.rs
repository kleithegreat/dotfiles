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
    collections::HashMap,
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
    Answer {
        id: u64,
        accept: bool,
    },
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
        let mut bytes = [0u8; 8];
        getrandom::fill(&mut bytes).map_err(|error| io::Error::other(error.to_string()))?;
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
                eprintln!("desktopctl: airdrop: offer thumbnail not drawable: {}", head.join(" "));
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
    tasks: Tasks,
}

struct Actor {
    conn: zbus::Connection,
    radio: RadioProxy<'static>,
    internal: mpsc::UnboundedSender<Internal>,
    controller: AirDropController,
    status: Status,
    name: String,
    want_visible: Option<Instant>,
    want_share: Option<Outgoing>,
    lease: Option<Lease>,
    acquiring: bool,
    /// The lease being given back, until owlyd says it is idle.
    releasing: Option<u64>,
    receiving: Option<Receiving>,
    sharing: Option<Sharing>,
}

pub async fn run(
    controller: AirDropController,
    mut shutdown: watch::Receiver<bool>,
) -> crate::Result<()> {
    let mut inbox = controller
        .inbox
        .lock()
        .map_err(|_| io::Error::other("airdrop lock poisoned"))?
        .take()
        .ok_or_else(|| io::Error::other("airdrop already running"))?;
    // owly-airdrop leaves rustls's provider to its caller.
    let _ = rustls::crypto::ring::default_provider().install_default();
    let conn = zbus::Connection::system().await?;
    let radio = RadioProxy::builder(&conn)
        .cache_properties(zbus::proxy::CacheProperties::No)
        .build()
        .await?;
    let mut states = radio.receive_state_changed().await?;
    let (internal, mut internals) = mpsc::unbounded_channel();
    let mut actor = Actor {
        status: Status {
            mode: probe(&radio).await,
            ..Status::default()
        },
        conn,
        radio,
        internal,
        controller,
        name: hostname(),
        want_visible: None,
        want_share: None,
        lease: None,
        acquiring: false,
        releasing: None,
        receiving: None,
        sharing: None,
    };
    actor.publish();

    loop {
        let deadline = actor.want_visible;
        tokio::select! {
            Some((command, reply)) = inbox.recv() => {
                let _ = reply.send(actor.command(command));
            }
            Some(event) = internals.recv() => actor.internal(event),
            Some(signal) = states.next() => {
                if let Ok(args) = signal.args() {
                    actor.radio_state(args.lease, &args.state, &args.reason);
                }
            }
            () = tokio::time::sleep_until(deadline.unwrap_or_else(Instant::now)), if deadline.is_some() => {
                actor.want_visible = None;
            }
            // owlyd ends a lease whose owner leaves the bus, so exiting gives the radio back.
            _ = shutdown.changed() => return Ok(()),
        }
        actor.reconcile().await;
        actor.publish();
    }
}

/// How the radio runs here, or `None` when AirDrop cannot use it.
async fn probe(radio: &RadioProxy<'_>) -> Option<String> {
    let report: Value = match radio.probe().await {
        Ok(report) => serde_json::from_str(&report).ok()?,
        Err(error) => {
            eprintln!("desktopctl: airdrop: owlyd unreachable: {error}");
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

impl Actor {
    fn command(&mut self, command: Command) -> Result<(), String> {
        match command {
            Command::Visible(true) => {
                self.status
                    .mode
                    .as_ref()
                    .ok_or("AirDrop has no radio it can use here")?;
                self.want_visible = Some(Instant::now() + airdrop::VISIBLE_FOR);
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
                self.sharing = None;
                self.status.share = Some(Share {
                    kind: outgoing.kind,
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
                let &(addr, flags) = sharing.found.get(&id).ok_or("that receiver is gone")?;
                let to = share
                    .receivers
                    .iter()
                    .find(|receiver| receiver.id == id)
                    .map(|receiver| receiver.name.clone())
                    .unwrap_or_default();
                share.sending = Some(Sending {
                    to,
                    state: "asking",
                    sent: 0,
                    total: 0,
                    error: None,
                });
                sharing.tasks.0.push(send_to(
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
                self.acquiring = false;
                match result {
                    Ok(lease) => self.lease = Some(lease),
                    Err(error) => self.give_up(&error),
                }
            }
            Internal::Released => self.releasing = None,
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
                sending.state = "sending";
                if let send::Event::Progress(progress) = progress {
                    sending.sent = progress.sent;
                    sending.total = progress.total;
                }
            }
            Internal::Sent(outcome) => {
                let Some(sending) = self
                    .status
                    .share
                    .as_mut()
                    .and_then(|share| share.sending.as_mut())
                else {
                    return;
                };
                (sending.state, sending.error) = match outcome {
                    Ok(Outcome::Delivered) => ("sent", None),
                    Ok(Outcome::Declined) => ("declined", None),
                    Ok(Outcome::Failed(reason)) | Err(reason) => ("failed", Some(reason)),
                };
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
        if self.releasing == Some(lease) {
            self.releasing = None;
        } else if self.lease.as_ref().is_some_and(|ours| ours.id == lease) {
            self.lease = None;
            self.give_up(reason);
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

    async fn reconcile(&mut self) {
        let wanted = self.want_visible.is_some() || self.want_share.is_some();
        if wanted && self.lease.is_none() && !self.acquiring {
            self.acquiring = true;
            tokio::spawn(acquire(self.radio.clone(), self.internal.clone()));
        }
        if self.want_visible.is_none() {
            self.receiving = None;
            self.status.requests.clear();
        }
        if self.want_share.is_none() {
            self.stop_sharing();
        }
        if !wanted {
            if let Some(lease) = self.lease.take() {
                self.releasing = Some(lease.id);
                tokio::spawn(release(self.radio.clone(), lease.id, self.internal.clone()));
            }
            return;
        }
        let Some(lease) = self.lease.clone() else {
            return;
        };

        if self.want_visible.is_some() && self.receiving.is_none() {
            match self.start_receiving(&lease).await {
                Ok(receiving) => self.receiving = Some(receiving),
                Err(error) => {
                    self.want_visible = None;
                    self.give_up(&format!("Receiving failed: {error}"));
                }
            }
        }
        if let Some(outgoing) = &self.want_share
            && self.sharing.is_none()
        {
            match self.start_sharing(&lease, outgoing.payload.clone()).await {
                Ok(sharing) => self.sharing = Some(sharing),
                Err(error) => self.give_up(&format!("Sharing failed: {error}")),
            }
        }
    }

    fn stop_sharing(&mut self) {
        if let Some(sharing) = self.sharing.take()
            && let Some(advert) = sharing.advert
        {
            tokio::spawn(advert.stop());
        }
    }

    async fn start_receiving(&self, lease: &Lease) -> io::Result<Receiving> {
        let identity = Identity::load_or_generate(&identity_dir()?)?;
        let destination = airdrop::downloads().map_err(io::Error::other)?;
        let addr = SocketAddrV6::new(lease.address, RECEIVE_PORT, 0, lease.index);
        let options = Options::new(ReceiverConfig::new(self.name.clone()), destination);
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
        let internal = self.internal.clone();
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
            self.name.clone(),
            service_id()?,
        ))?);
        let advert = Advertising::start(&self.conn)
            .await
            .inspect_err(|error| {
                eprintln!(
                    "desktopctl: airdrop: no BLE advert, so asleep iPhones stay asleep: {error}"
                )
            })
            .ok();
        let mut browse = Mdns::new(lease.index).browse().await?;
        let index = lease.index;

        let by_mdns = tokio::spawn({
            let (sender, internal) = (sender.clone(), self.internal.clone());
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
            let (sender, internal, radio) =
                (sender.clone(), self.internal.clone(), self.radio.clone());
            async move {
                loop {
                    for mac in peers(&radio).await {
                        let Some(address) = airdrop::link_local(&mac) else {
                            continue;
                        };
                        let addr = SocketAddrV6::new(address, AIRDROP_PORT, 0, index);
                        let Ok(Ok(Some(receiver))) =
                            tokio::time::timeout(KNOCK, sender.discover(addr)).await
                        else {
                            continue;
                        };
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
            tasks: Tasks(vec![by_mdns, by_peers]),
        })
    }

    fn publish(&self) {
        let mut status = self.status.clone();
        status.busy = self.acquiring || self.releasing.is_some();
        status.visible_until = self.want_visible.map(|deadline| {
            let left = deadline.saturating_duration_since(Instant::now());
            (SystemTime::now() + left)
                .duration_since(UNIX_EPOCH)
                .map_or(0, |since| since.as_secs())
        });
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
        eprintln!("desktopctl: airdrop: releasing the radio: {error}");
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
}
