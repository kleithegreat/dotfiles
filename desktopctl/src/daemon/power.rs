mod history;
mod processes;

use crate::daemon::{
    SubsystemHealth, focus::DesktopResolver, monitors::SharedPanelHz, server::Events,
};
use rusqlite::{Connection, params};
use std::{
    fs, io,
    path::{Path, PathBuf},
    str::FromStr,
    sync::{Arc, Mutex},
    time::Duration,
};
use tokio::{sync::watch, time::MissedTickBehavior};

const PERIOD: Duration = Duration::from_secs(5);
const SUMMARY_PERIOD: Duration = Duration::from_secs(60);
const RAPL_DOMAINS: [&str; 4] = ["psys", "package-0", "core", "uncore"];

#[zbus::proxy(
    interface = "org.freedesktop.UPower.PowerProfiles",
    default_service = "org.freedesktop.UPower.PowerProfiles",
    default_path = "/org/freedesktop/UPower/PowerProfiles"
)]
trait PowerProfiles {
    #[zbus(property)]
    fn active_profile(&self) -> zbus::Result<String>;
}

pub struct Sources {
    battery: PathBuf,
    counters: [Option<Counter>; 4],
    backlight: Option<PathBuf>,
}

struct Counter {
    energy: PathBuf,
    range: u64,
}

impl Sources {
    /// `None` on a machine without a system battery.
    pub fn discover() -> Option<Self> {
        let battery = fs::read_dir("/sys/class/power_supply")
            .ok()?
            .flatten()
            .map(|entry| entry.path())
            .find(|path| {
                read_trimmed(&path.join("type")).ok().as_deref() == Some("Battery")
                    && read_trimmed(&path.join("scope")).ok().as_deref() != Some("Device")
            })?;

        let mut counters = [None, None, None, None];
        for entry in fs::read_dir("/sys/class/powercap")
            .into_iter()
            .flatten()
            .flatten()
        {
            // intel-rapl-mmio:0 is package-0 again, through MMIO.
            if !entry
                .file_name()
                .to_string_lossy()
                .starts_with("intel-rapl:")
            {
                continue;
            }
            let path = entry.path();
            let Ok(name) = read_trimmed(&path.join("name")) else {
                continue;
            };
            let Some(index) = RAPL_DOMAINS.iter().position(|domain| *domain == name) else {
                continue;
            };
            if let Ok(range) = read_number(&path.join("max_energy_range_uj")) {
                counters[index] = Some(Counter {
                    energy: path.join("energy_uj"),
                    range,
                });
            }
        }

        let backlight = fs::read_dir("/sys/class/backlight")
            .ok()
            .and_then(|mut entries| entries.next())
            .and_then(Result::ok)
            .map(|entry| entry.path());

        Some(Self {
            battery,
            counters,
            backlight,
        })
    }

    fn read(&self) -> io::Result<Reading> {
        let current_ua: f64 = read_number(&self.battery.join("current_now"))?;
        let voltage_uv: f64 = read_number(&self.battery.join("voltage_now"))?;
        let discharging = read_trimmed(&self.battery.join("status"))? == "Discharging";
        Ok(Reading {
            boottime: boottime(),
            discharging,
            battery_w: current_ua * voltage_uv / 1e12,
            charge_uah: read_number(&self.battery.join("charge_now"))?,
            energy: self.counters.each_ref().map(|counter| {
                let counter = counter.as_ref()?;
                Some(Energy {
                    uj: read_number(&counter.energy).ok()?,
                    range: counter.range,
                })
            }),
            cpu: parse_cpu_times(&fs::read_to_string("/proc/stat")?),
            processes: if discharging {
                processes::snapshot()
            } else {
                Default::default()
            },
        })
    }

    fn backlight(&self) -> Option<f64> {
        let path = self.backlight.as_ref()?;
        let actual: f64 = read_number(&path.join("actual_brightness")).ok()?;
        let max: f64 = read_number(&path.join("max_brightness")).ok()?;
        (max > 0.0).then(|| actual / max)
    }
}

/// The latest 24-hour summary, for subscription snapshots; empty without a battery.
#[derive(Clone, Default)]
pub struct PowerHistory(Arc<Mutex<Option<serde_json::Value>>>);

impl PowerHistory {
    pub fn latest(&self) -> Option<serde_json::Value> {
        self.0.lock().ok()?.clone()
    }
}

/// Records one row per interval spent wholly on battery and awake, attributed
/// to the same class the focus tracker credits, and publishes the 24-hour
/// summary each minute.
pub struct PowerContext {
    pub attributed_class: Arc<Mutex<String>>,
    pub resolver: Arc<DesktopResolver>,
    pub panel_hz: SharedPanelHz,
    pub history: PowerHistory,
    pub events: Events,
    pub system_bus: Option<zbus::Connection>,
}

pub async fn run(
    sources: Sources,
    ctx: PowerContext,
    mut shutdown: watch::Receiver<bool>,
    health: SubsystemHealth,
) -> crate::Result<()> {
    let PowerContext {
        attributed_class,
        resolver,
        panel_hz,
        history,
        events,
        system_bus,
    } = ctx;
    let profiles = match &system_bus {
        Some(bus) => match power_profiles(bus).await {
            Ok(proxy) => Some(proxy),
            Err(error) => {
                tracing::warn!(error = %error, "power samples will carry no profile");
                None
            }
        },
        None => None,
    };
    let battery = sources
        .battery
        .file_name()
        .unwrap_or_default()
        .to_string_lossy();
    let device = match &system_bus {
        Some(bus) => match history::upower_device(bus, &battery).await {
            Ok(device) => Some(device),
            Err(error) => {
                tracing::warn!(error = %error, "the battery level chart will stay empty");
                None
            }
        },
        None => None,
    };
    let mut connection = init_db()?;
    let mut ticks = tokio::time::interval(PERIOD);
    ticks.set_missed_tick_behavior(MissedTickBehavior::Delay);
    let mut summaries = tokio::time::interval(SUMMARY_PERIOD);
    summaries.set_missed_tick_behavior(MissedTickBehavior::Delay);
    let mut previous: Option<Reading> = None;
    health.set_running("power sampler");

    loop {
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    health.set_stopped("power sampler");
                    return Ok(());
                }
            }
            _ = summaries.tick() => {
                let points = match &device {
                    Some(device) => history::charge_points(device).await,
                    None => Vec::new(),
                };
                let now = chrono::Utc::now().timestamp();
                if let Err(error) = tokio::task::block_in_place(|| prune_old_samples(&mut connection, now)) {
                    tracing::warn!(error = %error, "power retention prune failed");
                }
                match tokio::task::block_in_place(|| history::summary(&connection, &resolver, &points, now))
                    .and_then(|summary| Ok(serde_json::to_value(summary)?))
                {
                    Ok(summary) => {
                        if let Ok(mut latest) = history.0.lock() {
                            *latest = Some(summary.clone());
                        }
                        events.publish("power.changed", summary);
                        health.set_running("power sampler");
                    }
                    Err(error) => {
                        tracing::warn!(error = %error, "power summary failed");
                        health.set_degraded("power sampler", error.to_string());
                    }
                }
                continue;
            }
            _ = ticks.tick() => {}
        }

        let current_result = tokio::task::block_in_place(|| sources.read());
        let current = match current_result {
            Ok(reading) => reading,
            Err(error) => {
                tracing::warn!(error = %error, "power reading failed");
                health.set_degraded("power sampler", error.to_string());
                previous = None;
                continue;
            }
        };
        let sample = previous
            .as_ref()
            .and_then(|prev| Sample::between(prev, &current));
        let profile = match (&sample, &profiles) {
            (Some(_), Some(proxy)) => proxy.active_profile().await.ok(),
            _ => None,
        };
        let hz = panel_hz.lock().ok().and_then(|value| *value);
        tokio::task::block_in_place(|| -> crate::Result<()> {
            if let (Some(previous), Some(sample)) = (&previous, sample) {
                let shares = processes::attribute(&previous.processes, &current.processes, &sample);
                let tags = Tags {
                    profile,
                    app_class: attributed_class
                        .lock()
                        .map(|class| class.clone())
                        .unwrap_or_default(),
                    panel_hz: hz,
                    backlight: sources.backlight(),
                };
                insert(&mut connection, &sample, &tags, &shares)?;
            }
            previous = Some(current);
            health.set_running("power sampler");
            Ok(())
        })?;
    }
}

async fn power_profiles(
    connection: &zbus::Connection,
) -> zbus::Result<PowerProfilesProxy<'static>> {
    PowerProfilesProxy::new(connection).await
}

fn init_db() -> crate::Result<Connection> {
    let connection = crate::db::open_state_db()?;
    connection.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS power_samples (
            id         INTEGER PRIMARY KEY,
            ts         INTEGER NOT NULL,
            seconds    REAL NOT NULL,
            battery_w  REAL NOT NULL,
            charge_uah INTEGER NOT NULL,
            psys_w     REAL,
            package_w  REAL,
            core_w     REAL,
            uncore_w   REAL,
            cpu_busy   REAL,
            profile    TEXT,
            app_class  TEXT,
            panel_hz   REAL,
            backlight  REAL
        );
        CREATE TABLE IF NOT EXISTS power_processes (
            sample     INTEGER NOT NULL REFERENCES power_samples (id),
            name       TEXT NOT NULL,
            cpu_w      REAL,
            gpu_w      REAL,
            runs_per_s REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS power_samples_ts ON power_samples (ts);
        CREATE INDEX IF NOT EXISTS power_processes_sample ON power_processes (sample);
        ",
    )?;
    Ok(connection)
}

const RETENTION_SECONDS: i64 = 7 * 24 * 60 * 60;

fn prune_old_samples(connection: &mut Connection, now: i64) -> crate::Result<()> {
    let cutoff = now - RETENTION_SECONDS;
    let transaction = connection.transaction()?;
    transaction.execute(
        "DELETE FROM power_processes WHERE sample IN (SELECT id FROM power_samples WHERE ts < ?1)",
        [cutoff],
    )?;
    transaction.execute("DELETE FROM power_samples WHERE ts < ?1", [cutoff])?;
    transaction.commit()?;
    Ok(())
}

fn insert(
    connection: &mut Connection,
    sample: &Sample,
    tags: &Tags,
    shares: &[processes::Share],
) -> crate::Result<()> {
    let [psys_w, package_w, core_w, uncore_w] = sample.watts;
    let transaction = connection.transaction()?;
    transaction.execute(
        "INSERT INTO power_samples (
            ts, seconds, battery_w, charge_uah, psys_w, package_w, core_w, uncore_w,
            cpu_busy, profile, app_class, panel_hz, backlight
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        params![
            chrono::Utc::now().timestamp(),
            sample.seconds,
            sample.battery_w,
            sample.charge_uah,
            psys_w,
            package_w,
            core_w,
            uncore_w,
            sample.cpu_busy,
            tags.profile,
            Some(tags.app_class.as_str()).filter(|class| !class.is_empty()),
            tags.panel_hz,
            tags.backlight,
        ],
    )?;
    let id = transaction.last_insert_rowid();
    for share in shares {
        transaction.execute(
            "INSERT INTO power_processes (sample, name, cpu_w, gpu_w, runs_per_s)
             VALUES (?, ?, ?, ?, ?)",
            params![id, share.name, share.cpu_w, share.gpu_w, share.runs_per_s],
        )?;
    }
    transaction.commit()?;
    Ok(())
}

struct Reading {
    boottime: Duration,
    discharging: bool,
    battery_w: f64,
    charge_uah: i64,
    energy: [Option<Energy>; 4],
    cpu: Option<CpuTimes>,
    processes: processes::Snapshot,
}

#[derive(Clone, Copy)]
struct Energy {
    uj: u64,
    range: u64,
}

#[derive(Clone, Copy, Debug, PartialEq)]
struct CpuTimes {
    busy: u64,
    total: u64,
}

#[derive(Debug, PartialEq)]
struct Sample {
    seconds: f64,
    battery_w: f64,
    charge_uah: i64,
    watts: [Option<f64>; 4],
    busy_ticks: Option<u64>,
    cpu_busy: Option<f64>,
}

struct Tags {
    profile: Option<String>,
    app_class: String,
    panel_hz: Option<f64>,
    backlight: Option<f64>,
}

impl Sample {
    fn between(previous: &Reading, current: &Reading) -> Option<Self> {
        if !(previous.discharging && current.discharging) {
            return None;
        }
        let seconds = current
            .boottime
            .checked_sub(previous.boottime)?
            .as_secs_f64();
        // Boot time counts suspend and the tick clock does not, so a long gap spanned one.
        if seconds <= 0.0 || seconds > 2.0 * PERIOD.as_secs_f64() {
            return None;
        }

        let mut watts = [None; 4];
        for (watts, (previous, current)) in watts
            .iter_mut()
            .zip(previous.energy.iter().zip(&current.energy))
        {
            if let (Some(previous), Some(current)) = (previous, current) {
                *watts = Some(
                    energy_delta(previous.uj, current.uj, current.range) as f64 / 1e6 / seconds,
                );
            }
        }

        let (busy_ticks, cpu_busy) = match (previous.cpu, current.cpu) {
            (Some(previous), Some(current)) if current.total > previous.total => {
                let busy = current.busy.saturating_sub(previous.busy);
                (
                    Some(busy),
                    Some(busy as f64 / (current.total - previous.total) as f64),
                )
            }
            _ => (None, None),
        };

        Some(Self {
            seconds,
            battery_w: current.battery_w,
            charge_uah: current.charge_uah,
            watts,
            busy_ticks,
            cpu_busy,
        })
    }
}

fn energy_delta(previous: u64, current: u64, range: u64) -> u64 {
    if current >= previous {
        current - previous
    } else {
        range.saturating_sub(previous).saturating_add(current)
    }
}

/// Aggregate CPU jiffies from `/proc/stat`'s first line; guest time is already
/// inside user and nice.
fn parse_cpu_times(stat: &str) -> Option<CpuTimes> {
    let fields: Vec<u64> = stat
        .lines()
        .next()?
        .strip_prefix("cpu ")?
        .split_whitespace()
        .take(8)
        .map(str::parse)
        .collect::<Result<_, _>>()
        .ok()?;
    let [user, nice, system, idle, iowait, irq, softirq, steal] = fields.try_into().ok()?;
    let busy = user + nice + system + irq + softirq + steal;
    Some(CpuTimes {
        busy,
        total: busy + idle + iowait,
    })
}

fn boottime() -> Duration {
    let mut time = libc::timespec {
        tv_sec: 0,
        tv_nsec: 0,
    };
    unsafe { libc::clock_gettime(libc::CLOCK_BOOTTIME, &mut time) };
    Duration::new(time.tv_sec as u64, time.tv_nsec as u32)
}

fn read_trimmed(path: &Path) -> io::Result<String> {
    Ok(fs::read_to_string(path)?.trim().to_owned())
}

fn read_number<T: FromStr>(path: &Path) -> io::Result<T> {
    read_trimmed(path)?.parse().map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("{} is not a number", path.display()),
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn reading(seconds: u64, discharging: bool, uj: u64, busy: u64, total: u64) -> Reading {
        Reading {
            boottime: Duration::from_secs(seconds),
            discharging,
            battery_w: 20.0,
            charge_uah: 1_000_000,
            energy: [
                Some(Energy {
                    uj,
                    range: 1_000_000_000,
                }),
                None,
                None,
                None,
            ],
            cpu: Some(CpuTimes { busy, total }),
            processes: Default::default(),
        }
    }

    #[test]
    fn sample_between_averages_valid_intervals_and_drops_ac_or_suspend() {
        let sample = Sample::between(
            &reading(100, true, 0, 100, 1_000),
            &reading(105, true, 100_000_000, 150, 1_200),
        )
        .expect("sample");
        assert_eq!(sample.seconds, 5.0);
        assert_eq!(sample.watts, [Some(20.0), None, None, None]);
        assert_eq!(sample.cpu_busy, Some(0.25));

        for (prev, curr, label) in [
            (
                reading(0, false, 0, 0, 1),
                reading(5, true, 1, 1, 2),
                "ac->dc",
            ),
            (
                reading(0, true, 0, 0, 1),
                reading(5, false, 1, 1, 2),
                "dc->ac",
            ),
            (
                reading(0, true, 0, 0, 1),
                reading(600, true, 1, 1, 2),
                "suspend gap",
            ),
        ] {
            assert!(Sample::between(&prev, &curr).is_none(), "{label}");
        }
    }

    #[test]
    fn energy_counter_wraps_at_its_range() {
        assert_eq!(energy_delta(10, 25, 100), 15);
        assert_eq!(energy_delta(90, 5, 100), 15);
        assert_eq!(energy_delta(200, 5, 100), 5);
    }

    #[test]
    fn prune_old_samples_removes_rows_older_than_seven_days() {
        let mut conn = Connection::open_in_memory().expect("sqlite");
        conn.execute_batch(
            "CREATE TABLE power_samples (id INTEGER PRIMARY KEY, ts INTEGER NOT NULL);
             CREATE TABLE power_processes (sample INTEGER NOT NULL REFERENCES power_samples(id));",
        )
        .expect("schema");
        let now = 10_000_000;
        let stale_ts = now - RETENTION_SECONDS - 1;
        let fresh_ts = now - RETENTION_SECONDS + 1;
        conn.execute(
            "INSERT INTO power_samples (id, ts) VALUES (1, ?), (2, ?)",
            [stale_ts, fresh_ts],
        )
        .expect("samples");
        conn.execute("INSERT INTO power_processes (sample) VALUES (1), (2)", [])
            .expect("processes");

        prune_old_samples(&mut conn, now).expect("prune succeeds");

        let remaining_samples: Vec<i64> = conn
            .prepare("SELECT id FROM power_samples")
            .expect("stmt")
            .query_map([], |r| r.get(0))
            .expect("rows")
            .collect::<Result<_, _>>()
            .expect("collect");
        let remaining_procs: Vec<i64> = conn
            .prepare("SELECT sample FROM power_processes")
            .expect("stmt")
            .query_map([], |r| r.get(0))
            .expect("rows")
            .collect::<Result<_, _>>()
            .expect("collect");
        assert_eq!(remaining_samples, vec![2]);
        assert_eq!(remaining_procs, vec![2]);
    }

    #[test]
    fn cpu_times_split_idle_and_iowait_from_busy() {
        let stat = "cpu  10 20 30 400 50 6 7 8 9 10\ncpu0 1 2 3 4 5 6 7 8 9 10\n";
        assert_eq!(
            parse_cpu_times(stat),
            Some(CpuTimes {
                busy: 10 + 20 + 30 + 6 + 7 + 8,
                total: 10 + 20 + 30 + 400 + 50 + 6 + 7 + 8,
            })
        );
    }
}
