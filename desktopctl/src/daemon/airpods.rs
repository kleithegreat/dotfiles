//! Finds AirPods through BlueZ: cases in reach through a passive advertisement
//! monitor, and a connected pair, which gets an AAP channel ([[airpods]]).

use crate::{
    airpods::{self, Link, Nearby, NoiseMode},
    daemon::server::Events,
    l2cap::Channel,
};
use futures_util::{FutureExt, StreamExt};
use serde_json::Value;
use std::{
    collections::{HashMap, HashSet},
    io,
    sync::{Arc, Mutex, MutexGuard},
    time::Duration,
};
use tokio::{
    sync::{Notify, watch},
    task::JoinHandle,
};
use zbus::{
    MatchRule, MessageStream, OwnedObjectPath, OwnedVariant,
    fdo::{ManagedObjects, ObjectManager, ObjectManagerProxy},
};

const BLUEZ: &str = "org.bluez";
const ADAPTER: &str = "org.bluez.Adapter1";
const DEVICE: &str = "org.bluez.Device1";
const MONITOR_MANAGER: &str = "org.bluez.AdvertisementMonitorManager1";
const MONITORS: &str = "/desktopctl/airpods";
const MONITOR: &str = "/desktopctl/airpods/proximity";
/// Signals arrive one property at a time; one look covers the burst.
const SETTLE: Duration = Duration::from_millis(150);
const RETRY: Duration = Duration::from_secs(30);

#[derive(Clone)]
pub struct AirPodsController {
    shared: Arc<Mutex<Shared>>,
    wake: Arc<Notify>,
    events: Events,
}

#[derive(Default)]
struct Shared {
    link: Option<Link>,
    channel: Option<Arc<Channel>>,
    /// Devices the monitor last reported in reach.
    near: HashSet<OwnedObjectPath>,
    nearby: Option<Nearby>,
    published: Value,
}

impl Shared {
    fn status(&self) -> Value {
        serde_json::json!({ "link": self.link, "nearby": self.nearby })
    }
}

impl AirPodsController {
    pub fn new(events: Events) -> Self {
        Self {
            shared: Arc::default(),
            wake: Arc::default(),
            events,
        }
    }

    pub fn status(&self) -> crate::Result<Value> {
        Ok(self.lock()?.status())
    }

    /// Settles when the pair echoes the setting, as `airpods.changed`.
    pub async fn set_noise(&self, mode: NoiseMode) -> crate::Result<Value> {
        self.send(&airpods::set_noise(mode)).await
    }

    pub async fn set_awareness(&self, enabled: bool) -> crate::Result<Value> {
        self.send(&airpods::set_awareness(enabled)).await
    }

    async fn send(&self, packet: &[u8]) -> crate::Result<Value> {
        let channel = self.lock()?.channel.clone();
        let channel = channel.ok_or_else(|| io::Error::other("no AirPods are connected"))?;
        channel.send(packet).await?;
        Ok(Value::Object(Default::default()))
    }

    fn update(&self, change: impl FnOnce(&mut Shared)) {
        let Ok(mut shared) = self.lock() else { return };
        change(&mut shared);
        let status = shared.status();
        if status != shared.published {
            shared.published = status.clone();
            self.events.publish("airpods.changed", status);
        }
    }

    fn lock(&self) -> crate::Result<MutexGuard<'_, Shared>> {
        self.shared
            .lock()
            .map_err(|_| io::Error::other("airpods state lock poisoned").into())
    }
}

/// BlueZ calls this back: which proximity adverts are strong enough to count.
struct Monitor(AirPodsController);

#[zbus::interface(name = "org.bluez.AdvertisementMonitor1")]
impl Monitor {
    fn release(&self) {}

    fn activate(&self) {}

    fn device_found(&self, device: OwnedObjectPath) {
        self.near(device, true);
    }

    fn device_lost(&self, device: OwnedObjectPath) {
        self.near(device, false);
    }

    #[zbus(property, name = "Type")]
    fn kind(&self) -> &str {
        "or_patterns"
    }

    #[zbus(property)]
    fn patterns(&self) -> Vec<(u8, u8, Vec<u8>)> {
        let [low, high] = airpods::APPLE.to_le_bytes();
        vec![(0, 0xff, vec![low, high, airpods::PROXIMITY])]
    }

    // Roughly arm's length, as an iPhone shows its card.
    #[zbus(property, name = "RSSIHighThreshold")]
    fn rssi_high_threshold(&self) -> i16 {
        -60
    }

    #[zbus(property, name = "RSSIHighTimeout")]
    fn rssi_high_timeout(&self) -> u16 {
        1
    }

    #[zbus(property, name = "RSSILowThreshold")]
    fn rssi_low_threshold(&self) -> i16 {
        -80
    }

    #[zbus(property, name = "RSSILowTimeout")]
    fn rssi_low_timeout(&self) -> u16 {
        5
    }

    /// Every advert, so a lid closing or a pod leaving the case shows at once.
    #[zbus(property, name = "RSSISamplingPeriod")]
    fn rssi_sampling_period(&self) -> u16 {
        0
    }
}

impl Monitor {
    fn near(&self, device: OwnedObjectPath, found: bool) {
        if let Ok(mut shared) = self.0.lock() {
            match found {
                true => shared.near.insert(device),
                false => shared.near.remove(&device),
            };
        }
        self.0.wake.notify_one();
    }
}

#[zbus::proxy(
    interface = "org.bluez.AdvertisementMonitorManager1",
    default_service = "org.bluez"
)]
trait MonitorManager {
    fn register_monitor(&self, application: &zbus::ObjectPath<'_>) -> zbus::Result<()>;
}

pub async fn run(
    controller: AirPodsController,
    mut shutdown: watch::Receiver<bool>,
) -> crate::Result<()> {
    let connection = zbus::Connection::system().await?;
    let server = connection.object_server();
    server.at(MONITORS, ObjectManager).await?;
    server.at(MONITOR, Monitor(controller.clone())).await?;
    let bus = zbus::fdo::DBusProxy::new(&connection).await?;
    let bluez = ObjectManagerProxy::builder(&connection)
        .destination(BLUEZ)
        .path("/")
        .build()
        .await?;
    let rule = MatchRule::builder()
        .msg_type(zbus::message::Type::Signal)
        .sender(BLUEZ)
        .build()?;
    let mut signals = MessageStream::for_match_rule(rule, &connection, None).await?;
    let mut watcher = Watcher::default();

    loop {
        let owner = bus.get_name_owner(BLUEZ.try_into()?).await;
        let healthy = match (owner, bluez.get_managed_objects().await) {
            (Ok(owner), Ok(objects)) => {
                watcher
                    .reconcile(&connection, owner.as_str(), &objects, &controller)
                    .await;
                true
            }
            (Err(error), _) | (_, Err(error)) => {
                eprintln!("desktopctl: airpods: BlueZ unreadable: {error}");
                false
            }
        };
        tokio::select! {
            signal = signals.next() => if signal.is_none() {
                return Ok(());
            },
            () = controller.wake.notified() => {}
            () = tokio::time::sleep(RETRY), if !healthy => {}
            _ = shutdown.changed() => {
                watcher.drop_link(&controller);
                return Ok(());
            }
        }
        tokio::time::sleep(SETTLE).await;
        while let Some(Some(_)) = signals.next().now_or_never() {}
    }
}

#[derive(Default)]
struct Watcher {
    /// bluetoothd's unique name and the adapter the monitor went to. A
    /// restarted bluetoothd keeps the adapter path but forgets the monitor.
    registered: Option<(String, OwnedObjectPath)>,
    link: Option<(OwnedObjectPath, JoinHandle<()>)>,
}

impl Watcher {
    async fn reconcile(
        &mut self,
        connection: &zbus::Connection,
        owner: &str,
        objects: &ManagedObjects,
        controller: &AirPodsController,
    ) {
        let has = |interfaces: &HashMap<_, _>, wanted: &str| {
            interfaces
                .keys()
                .any(|name: &zbus::names::OwnedInterfaceName| name.as_str() == wanted)
        };
        let adapter = objects.iter().find_map(|(path, interfaces)| {
            let adapter = interfaces
                .iter()
                .find(|(name, _)| name.as_str() == ADAPTER)?
                .1;
            Some((
                path,
                flag(adapter, "Powered"),
                has(interfaces, MONITOR_MANAGER),
            ))
        });
        let key = adapter.map(|(path, ..)| (owner.to_owned(), path.clone()));
        // bluetoothd drops a monitor added while the adapter is off ([[airpods]]).
        let ready = adapter.is_none_or(|(_, powered, _)| powered);
        if key != self.registered && ready {
            self.registered = key;
            let failure = match adapter {
                Some((path, _, true)) => register(connection, path)
                    .await
                    .err()
                    .map(|e| (path, e.to_string())),
                Some((path, _, false)) => Some((
                    path,
                    "bluetoothd is not running with Experimental = true".to_owned(),
                )),
                None => None,
            };
            if let Some((adapter, error)) = failure {
                eprintln!("desktopctl: airpods: no proximity monitor on {adapter}: {error}");
            }
        }

        let devices: HashMap<&OwnedObjectPath, &HashMap<String, OwnedVariant>> = objects
            .iter()
            .filter_map(|(path, interfaces)| {
                let device = interfaces
                    .iter()
                    .find(|(name, _)| name.as_str() == DEVICE)?
                    .1;
                Some((path, device))
            })
            .collect();

        let connected = devices.iter().find(|(_, device)| {
            flag(device, "Connected")
                && strings(device, "UUIDs")
                    .iter()
                    .any(|uuid| uuid == airpods::SERVICE_UUID)
        });
        let current = self.link.as_ref().map(|(path, _)| path);
        if current != connected.map(|(path, _)| *path) {
            self.drop_link(controller);
            if let Some((path, device)) = connected
                && let Some(address) = string(device, "Address")
            {
                let name = string(device, "Alias").unwrap_or_else(|| "AirPods".to_owned());
                let task = tokio::spawn(hold(controller.clone(), address, name));
                self.link = Some(((*path).clone(), task));
            }
        }

        let paired: HashMap<u16, String> = devices
            .values()
            .filter(|device| flag(device, "Paired"))
            .filter_map(|device| {
                let product = airpods::modalias_product(&string(device, "Modalias")?)?;
                Some((product, string(device, "Address")?))
            })
            .collect();
        controller.update(|shared| {
            shared.nearby = shared
                .near
                .iter()
                .filter_map(|path| devices.get(path))
                .filter_map(|device| {
                    let rssi = device.get("RSSI")?.downcast_ref::<i16>().ok()?;
                    airpods::proximity(&manufacturer(device)?, rssi)
                })
                .map(|nearby| Nearby {
                    paired: paired.get(&nearby.product).cloned(),
                    ..nearby
                })
                .max_by_key(|nearby| nearby.rssi);
        });
    }

    fn drop_link(&mut self, controller: &AirPodsController) {
        if let Some((_, task)) = self.link.take() {
            task.abort();
            controller.update(|shared| {
                shared.link = None;
                shared.channel = None;
            });
        }
    }
}

async fn register(connection: &zbus::Connection, adapter: &OwnedObjectPath) -> zbus::Result<()> {
    MonitorManagerProxy::builder(connection)
        .path(adapter.clone())
        .build()
        .await?
        .register_monitor(&zbus::ObjectPath::try_from(MONITORS)?)
        .await
}

/// Holds the channel for as long as BlueZ reports the pair connected; the
/// watcher aborts it when that ends. The channel can lag the ACL link coming
/// up, so failures retry.
async fn hold(controller: AirPodsController, address: String, name: String) {
    let mut backoff = Duration::from_secs(1);
    loop {
        if let Err(error) = session(&controller, &address, &name).await {
            eprintln!("desktopctl: airpods: channel to {address}: {error}");
        }
        controller.update(|shared| {
            shared.link = None;
            shared.channel = None;
        });
        tokio::time::sleep(backoff).await;
        backoff = (backoff * 2).min(RETRY);
    }
}

async fn session(controller: &AirPodsController, address: &str, name: &str) -> io::Result<()> {
    let channel = Arc::new(Channel::connect(address, airpods::PSM).await?);
    for packet in [
        &airpods::HANDSHAKE[..],
        &airpods::FEATURES,
        &airpods::NOTIFY,
    ] {
        channel.send(packet).await?;
    }
    controller.update(|shared| {
        shared.link = Some(Link {
            address: address.to_owned(),
            name: name.to_owned(),
            ..Link::default()
        });
        shared.channel = Some(channel.clone());
    });
    let mut buffer = [0; 1024];
    loop {
        let read = channel.recv(&mut buffer).await?;
        if read == 0 {
            return Ok(());
        }
        if let Some(update) = airpods::parse(&buffer[..read]) {
            controller.update(|shared| {
                if let Some(link) = &mut shared.link {
                    link.apply(update);
                }
            });
        }
    }
}

fn flag(device: &HashMap<String, OwnedVariant>, key: &str) -> bool {
    device
        .get(key)
        .and_then(|value| value.downcast_ref::<bool>().ok())
        .unwrap_or(false)
}

fn string(device: &HashMap<String, OwnedVariant>, key: &str) -> Option<String> {
    device.get(key)?.downcast_ref::<String>().ok()
}

fn strings(device: &HashMap<String, OwnedVariant>, key: &str) -> Vec<String> {
    device
        .get(key)
        .and_then(|value| <Vec<String>>::try_from(value.try_clone().ok()?).ok())
        .unwrap_or_default()
}

fn manufacturer(device: &HashMap<String, OwnedVariant>) -> Option<Vec<u8>> {
    let data =
        <HashMap<u16, OwnedVariant>>::try_from(device.get("ManufacturerData")?.try_clone().ok()?)
            .ok()?;
    <Vec<u8>>::try_from(data.get(&airpods::APPLE)?.try_clone().ok()?).ok()
}
