use crate::{
    daemon::{SubsystemHealth, hypr_events::HyprEvent, server::Events},
    hypr, paths,
};
use chrono::{Datelike, Duration, Local, NaiveDate};
use rusqlite::{Connection, params, params_from_iter};
use serde::{Serialize, Serializer};
use std::{
    collections::HashMap,
    fs,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
    time::Duration as StdDuration,
};
use tokio::{
    sync::{broadcast, watch},
    time::MissedTickBehavior,
};

const LOCKED_CLASS: &str = "__locked__";
const EXCLUDED_CLASSES: [&str; 3] = ["", "Desktop", "Quickshell"];

/// Latest focus summary for subscription snapshots.
#[derive(Clone, Default)]
pub struct FocusState(Arc<Mutex<Option<serde_json::Value>>>);

impl FocusState {
    pub fn latest(&self) -> Option<serde_json::Value> {
        self.0.lock().ok()?.clone()
    }
}

/// `attributed_class` receives the class each second is credited to.
pub async fn run(
    mut hypr_rx: broadcast::Receiver<HyprEvent>,
    attributed_class: Arc<Mutex<String>>,
    focus_state: FocusState,
    resolver: Arc<DesktopResolver>,
    events: Events,
    mut shutdown: watch::Receiver<bool>,
    health: SubsystemHealth,
) -> crate::Result<()> {
    let connection = init_db()?;
    let mut month_cache = MonthCache::default();
    let mut current_class = tokio::task::spawn_blocking(get_active_class)
        .await
        .unwrap_or_default();
    let mut ticks = tokio::time::interval(StdDuration::from_secs(1));
    ticks.set_missed_tick_behavior(MissedTickBehavior::Delay);
    health.set_running("focus tracker");

    loop {
        tokio::select! {
            changed = shutdown.changed() => {
                if changed.is_err() || *shutdown.borrow() {
                    health.set_stopped("focus tracker");
                    return Ok(());
                }
            }
            event = hypr_rx.recv() => match event {
                Ok(HyprEvent::Connected) | Err(broadcast::error::RecvError::Lagged(_)) => {
                    current_class = tokio::task::spawn_blocking(get_active_class)
                        .await
                        .unwrap_or_default();
                }
                Ok(HyprEvent::Line(line)) => {
                    if let Some(rest) = line.strip_prefix("activewindow>>") {
                        let class_name = rest
                            .split_once(',')
                            .map(|(class_name, _)| class_name)
                            .unwrap_or(rest);
                        current_class = class_name.to_owned();
                    }
                }
                Err(broadcast::error::RecvError::Closed) => {
                    health.set_stopped("focus tracker");
                    return Ok(());
                }
            },
            _ = ticks.tick() => {
                let class_snapshot = current_class.clone();
                let res = tokio::task::block_in_place(|| {
                    record_tick(
                        &connection,
                        &resolver,
                        &class_snapshot,
                        &attributed_class,
                        &focus_state,
                        &events,
                        &mut month_cache,
                    )
                });
                match res {
                    Ok(()) => health.set_running("focus tracker"),
                    Err(error) => {
                        tracing::warn!(error = %error, "focus tracker tick failed");
                        health.set_degraded("focus tracker", error.to_string());
                    }
                }
            }
        }
    }
}

#[derive(Default)]
struct MonthCache {
    cached_date: Option<NaiveDate>,
    past_sums: HashMap<String, i64>,
}

fn record_tick(
    connection: &Connection,
    resolver: &DesktopResolver,
    class_name: &str,
    attributed_class: &Arc<Mutex<String>>,
    focus_state: &FocusState,
    events: &Events,
    month_cache: &mut MonthCache,
) -> crate::Result<()> {
    let now = Local::now();
    let locked = is_screen_locked();
    let credited = if locked { LOCKED_CLASS } else { class_name };
    if !credited.is_empty() {
        accumulate(connection, credited, &now)?;
    }
    if let Ok(mut shared) = attributed_class.lock() {
        *shared = credited.to_owned();
    }

    let summary = build_summary(connection, resolver, class_name, locked, &now, month_cache)?;
    let payload = serde_json::to_value(&summary)?;
    if let Ok(mut latest) = focus_state.0.lock() {
        *latest = Some(payload.clone());
    }
    events.publish("focus.changed", payload);
    Ok(())
}

fn init_db() -> crate::Result<Connection> {
    let connection = crate::db::open_state_db()?;
    connection.execute_batch(
        "
        CREATE TABLE IF NOT EXISTS daily_totals (
            date      TEXT NOT NULL,
            app_class TEXT NOT NULL,
            seconds   INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, app_class)
        );
        ",
    )?;

    Ok(connection)
}

fn accumulate(
    connection: &Connection,
    app_class: &str,
    now: &chrono::DateTime<Local>,
) -> crate::Result<()> {
    let date = now.format("%Y-%m-%d").to_string();
    connection.execute(
        "INSERT INTO daily_totals (date, app_class, seconds) VALUES (?, ?, 1)
         ON CONFLICT(date, app_class) DO UPDATE SET seconds = seconds + 1",
        params![date, app_class],
    )?;

    Ok(())
}

fn build_summary(
    connection: &Connection,
    resolver: &DesktopResolver,
    current_class: &str,
    locked: bool,
    now: &chrono::DateTime<Local>,
    month_cache: &mut MonthCache,
) -> crate::Result<Summary> {
    let today = now.date_naive();
    let today_string = today.format("%Y-%m-%d").to_string();
    let weekday = i64::from(today.weekday().num_days_from_monday());
    let week_start = today - Duration::days(weekday);
    let week_end = week_start + Duration::days(6);
    let yesterday = today - Duration::days(1);
    let range_start = std::cmp::min(week_start, yesterday);

    let daily_sums = load_daily_sums(connection, range_start, week_end)?;
    let total = *daily_sums.get(&today_string).unwrap_or(&0);
    let yesterday_total = *daily_sums
        .get(&yesterday.format("%Y-%m-%d").to_string())
        .unwrap_or(&0);

    let mut week = Vec::with_capacity(7);
    let mut nonzero_week_totals = Vec::new();
    for offset in 0..7 {
        let date = week_start + Duration::days(offset);
        let date_string = date.format("%Y-%m-%d").to_string();
        let day_total = *daily_sums.get(&date_string).unwrap_or(&0);
        week.push(WeekEntry {
            date: date_string,
            day: date.format("%a").to_string(),
            total: day_total,
            is_target: date == today,
        });
        if day_total > 0 {
            nonzero_week_totals.push(day_total);
        }
    }

    let average = if nonzero_week_totals.is_empty() {
        0
    } else {
        round_half_even(
            nonzero_week_totals.iter().sum::<i64>(),
            nonzero_week_totals.len() as i64,
        )
    };
    let week_range = format!(
        "{} - {}",
        week_start.format("%b %-d"),
        week_end.format("%b %-d")
    );

    let apps = load_apps(connection, resolver, &today_string, total)?;
    let current = if locked {
        "Locked".to_owned()
    } else if current_class.is_empty() || EXCLUDED_CLASSES.contains(&current_class) {
        String::new()
    } else {
        resolver.resolve(current_class).0
    };

    let month = load_month(connection, today, total, month_cache)?;

    Ok(Summary {
        last_updated: now.timestamp(),
        total,
        average,
        week_range,
        yesterday: yesterday_total,
        current,
        apps,
        week,
        month,
    })
}

fn load_daily_sums(
    connection: &Connection,
    range_start: NaiveDate,
    range_end: NaiveDate,
) -> crate::Result<HashMap<String, i64>> {
    let mut statement = connection.prepare(
        "SELECT date, SUM(seconds)
         FROM daily_totals
         WHERE date BETWEEN ? AND ? AND app_class NOT IN (?, ?, ?, ?)
         GROUP BY date",
    )?;
    let (range_start, range_end) = (
        range_start.format("%Y-%m-%d").to_string(),
        range_end.format("%Y-%m-%d").to_string(),
    );
    let rows = statement.query_map(
        params_from_iter(
            [range_start.as_str(), range_end.as_str(), LOCKED_CLASS]
                .into_iter()
                .chain(EXCLUDED_CLASSES),
        ),
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
    )?;

    let mut sums = HashMap::new();
    for row in rows {
        let (date, total) = row?;
        sums.insert(date, total);
    }

    Ok(sums)
}

fn load_apps(
    connection: &Connection,
    resolver: &DesktopResolver,
    today: &str,
    total: i64,
) -> crate::Result<Vec<AppEntry>> {
    let mut statement = connection.prepare(
        "SELECT app_class, SUM(seconds)
         FROM daily_totals
         WHERE date = ? AND app_class != ?
         GROUP BY app_class
         ORDER BY SUM(seconds) DESC",
    )?;
    let rows = statement.query_map(params![today, LOCKED_CLASS], |row| {
        Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?))
    })?;

    let mut apps = Vec::new();
    for row in rows {
        let (class_name, seconds) = row?;
        if EXCLUDED_CLASSES.contains(&class_name.as_str()) {
            continue;
        }

        let (name, icon) = resolver.resolve(&class_name);
        apps.push(AppEntry {
            class_name,
            name,
            icon,
            seconds,
            percent: if total > 0 {
                Percent::Tenths(round_half_even(seconds * 1000, total))
            } else {
                Percent::Integer(0)
            },
        });
    }

    Ok(apps)
}

fn load_month(
    connection: &Connection,
    today: NaiveDate,
    today_total: i64,
    cache: &mut MonthCache,
) -> crate::Result<Vec<Option<MonthEntry>>> {
    let today_string = today.format("%Y-%m-%d").to_string();
    if cache.cached_date != Some(today) {
        let month_prefix = today.format("%Y-%m-").to_string();
        let mut statement = connection.prepare(
            "SELECT date, SUM(seconds)
             FROM daily_totals
             WHERE date LIKE ? AND date < ? AND app_class NOT IN (?, ?, ?, ?)
             GROUP BY date",
        )?;
        let month_pattern = format!("{month_prefix}%");
        let rows = statement.query_map(
            params_from_iter(
                [month_pattern.as_str(), today_string.as_str(), LOCKED_CLASS]
                    .into_iter()
                    .chain(EXCLUDED_CLASSES),
            ),
            |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
        )?;

        let mut past_sums = HashMap::new();
        for row in rows {
            let (date, total) = row?;
            past_sums.insert(date, total);
        }
        cache.past_sums = past_sums;
        cache.cached_date = Some(today);
    }

    let first_day = NaiveDate::from_ymd_opt(today.year(), today.month(), 1).expect("valid month");
    let first_weekday = first_day.weekday().num_days_from_monday() as usize;
    let next_month = if today.month() == 12 {
        NaiveDate::from_ymd_opt(today.year() + 1, 1, 1).expect("valid next year")
    } else {
        NaiveDate::from_ymd_opt(today.year(), today.month() + 1, 1).expect("valid next month")
    };
    let days_in_month = (next_month - first_day).num_days() as u32;

    let mut month = vec![None; first_weekday];
    for day in 1..=days_in_month {
        let date = NaiveDate::from_ymd_opt(today.year(), today.month(), day).expect("valid day");
        let date_string = date.format("%Y-%m-%d").to_string();
        let total = if date == today {
            today_total
        } else {
            *cache.past_sums.get(&date_string).unwrap_or(&0)
        };
        month.push(Some(MonthEntry {
            date: date_string,
            total,
            is_target: date == today,
        }));
    }

    Ok(month)
}

fn is_screen_locked() -> bool {
    crate::proc_util::is_process_running("hyprlock")
}

fn get_active_class() -> String {
    hypr::active_window()
        .map(|window| {
            if window.class.is_empty() {
                window.initial_class
            } else {
                window.class
            }
        })
        .unwrap_or_default()
}

fn round_half_even(numerator: i64, denominator: i64) -> i64 {
    if denominator == 0 {
        0
    } else {
        (numerator as f64 / denominator as f64).round_ties_even() as i64
    }
}

pub(crate) struct DesktopResolver {
    entries: HashMap<String, (String, String)>,
}

impl DesktopResolver {
    pub(crate) fn load() -> Self {
        let mut data_dirs = Vec::new();
        if let Ok(path) = paths::xdg_data_home() {
            data_dirs.push(path);
        }
        let xdg_data_dirs = std::env::var("XDG_DATA_DIRS")
            .unwrap_or_else(|_| "/usr/local/share:/usr/share".to_owned());
        data_dirs.extend(
            xdg_data_dirs
                .split(':')
                .filter(|path| !path.is_empty())
                .map(PathBuf::from),
        );

        let mut extra_paths = vec![PathBuf::from("/run/current-system/sw/share")];
        if let Ok(home) = paths::home_dir() {
            extra_paths.push(home.join(".nix-profile/share"));
        }
        for extra_path in extra_paths {
            if !data_dirs.iter().any(|path| path == &extra_path) {
                data_dirs.push(extra_path);
            }
        }

        let mut entries = HashMap::new();
        for data_dir in data_dirs {
            scan_desktop_dir(&data_dir.join("applications"), &mut entries);
        }

        Self { entries }
    }

    pub(crate) fn resolve(&self, window_class: &str) -> (String, String) {
        self.entries
            .get(&window_class.to_ascii_lowercase())
            .cloned()
            .unwrap_or_else(|| (window_class.to_owned(), String::new()))
    }
}

fn scan_desktop_dir(directory: &Path, entries: &mut HashMap<String, (String, String)>) {
    let Ok(read_dir) = fs::read_dir(directory) else {
        return;
    };

    for entry in read_dir.flatten() {
        let path = entry.path();
        if path.is_dir() {
            scan_desktop_dir(&path, entries);
            continue;
        }

        if path.extension().and_then(|ext| ext.to_str()) != Some("desktop") {
            continue;
        }

        parse_desktop_file(&path, entries);
    }
}

fn parse_desktop_file(path: &Path, entries: &mut HashMap<String, (String, String)>) {
    let Ok(contents) = fs::read_to_string(path) else {
        return;
    };

    let mut name = None;
    let mut icon = None;
    let mut startup_wm_class = None;
    let mut in_entry = false;

    for line in contents.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }

        let Some((key, value)) = line.split_once('=') else {
            continue;
        };
        let key = key.trim();
        let value = value.trim();
        if key == "Name" && name.is_none() {
            name = Some(value.to_owned());
        } else if key == "Icon" && icon.is_none() {
            icon = Some(value.to_owned());
        } else if key == "StartupWMClass" {
            startup_wm_class = Some(value.to_owned());
        }
    }

    let Some(name) = name else {
        return;
    };
    let icon = icon.unwrap_or_default();

    if let Some(startup_wm_class) = startup_wm_class {
        entries
            .entry(startup_wm_class.to_ascii_lowercase())
            .or_insert_with(|| (name.clone(), icon.clone()));
    }
    if let Some(stem) = path.file_stem().and_then(|stem| stem.to_str()) {
        entries
            .entry(stem.to_ascii_lowercase())
            .or_insert_with(|| (name, icon));
    }
}

#[derive(Serialize)]
struct Summary {
    last_updated: i64,
    total: i64,
    average: i64,
    week_range: String,
    yesterday: i64,
    current: String,
    apps: Vec<AppEntry>,
    week: Vec<WeekEntry>,
    month: Vec<Option<MonthEntry>>,
}

#[derive(Serialize)]
struct AppEntry {
    #[serde(rename = "class")]
    class_name: String,
    name: String,
    icon: String,
    seconds: i64,
    percent: Percent,
}

#[derive(Serialize)]
struct WeekEntry {
    date: String,
    day: String,
    total: i64,
    is_target: bool,
}

#[derive(Clone, Serialize)]
struct MonthEntry {
    date: String,
    total: i64,
    is_target: bool,
}

enum Percent {
    Integer(i64),
    Tenths(i64),
}

impl Serialize for Percent {
    fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        match self {
            // Tenths must render with one decimal digit (83.3, 100.0).
            Self::Integer(value) => serializer.serialize_i64(*value),
            Self::Tenths(value) => serializer.serialize_f64(*value as f64 / 10.0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock};
    use chrono::TimeZone;

    fn test_db() -> Connection {
        let connection = Connection::open_in_memory().expect("in-memory sqlite db");
        connection
            .execute_batch(
                "CREATE TABLE daily_totals (
                    date      TEXT NOT NULL,
                    app_class TEXT NOT NULL,
                    seconds   INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (date, app_class)
                );",
            )
            .expect("create daily_totals");
        connection
    }

    fn insert_total(connection: &Connection, date: &str, app_class: &str, seconds: i64) {
        connection
            .execute(
                "INSERT INTO daily_totals (date, app_class, seconds) VALUES (?, ?, ?)",
                params![date, app_class, seconds],
            )
            .expect("insert daily total");
    }

    #[test]
    fn summary_serialization_matches_the_runtime_contract() {
        let summary = Summary {
            last_updated: 1_765_000_000,
            total: 3600,
            average: 1800,
            week_range: "Jun 8 - Jun 14".to_owned(),
            yesterday: 1200,
            current: "Café".to_owned(),
            apps: vec![
                AppEntry {
                    class_name: "kitty".to_owned(),
                    name: "kitty".to_owned(),
                    icon: "kitty-icon".to_owned(),
                    seconds: 3000,
                    percent: Percent::Tenths(833),
                },
                AppEntry {
                    class_name: "single".to_owned(),
                    name: "Single".to_owned(),
                    icon: String::new(),
                    seconds: 3600,
                    percent: Percent::Tenths(1000),
                },
                AppEntry {
                    class_name: "tiny".to_owned(),
                    name: "Tiny".to_owned(),
                    icon: String::new(),
                    seconds: 1,
                    percent: Percent::Tenths(0),
                },
                AppEntry {
                    class_name: "café".to_owned(),
                    name: "Café".to_owned(),
                    icon: String::new(),
                    seconds: 600,
                    percent: Percent::Integer(0),
                },
            ],
            week: vec![WeekEntry {
                date: "2026-06-08".to_owned(),
                day: "Mon".to_owned(),
                total: 0,
                is_target: false,
            }],
            month: vec![
                None,
                Some(MonthEntry {
                    date: "2026-06-01".to_owned(),
                    total: 42,
                    is_target: true,
                }),
            ],
        };

        let rendered = serde_json::to_value(&summary).expect("summary should serialize");
        assert_eq!(rendered["total"], 3600);
        assert_eq!(rendered["current"], "Café");
        assert_eq!(rendered["apps"][0]["percent"], 83.3);
        assert_eq!(rendered["apps"][1]["percent"], 100.0);
        assert_eq!(rendered["apps"][2]["percent"], 0.0);
        assert_eq!(rendered["apps"][3]["percent"], 0);
        assert_eq!(rendered["month"][0], serde_json::Value::Null);
    }

    #[test]
    fn round_half_even_handles_ties_and_zero_denominator() {
        assert_eq!(round_half_even(5, 2), 2);
        assert_eq!(round_half_even(7, 2), 4);
        assert_eq!(round_half_even(99, 0), 0);
    }

    #[test]
    fn desktop_resolver_parses_desktop_entry_section_and_startup_wm_class() -> crate::Result<()> {
        let _lock = env_lock();
        let data_dir = TempDir::new("desktopctl-desktop-entries")?;
        let apps_dir = data_dir.path().join("applications/nested");
        fs::create_dir_all(&apps_dir)?;
        fs::write(
            apps_dir.join("org.example.Editor.desktop"),
            "[Desktop Entry]\nName=Example Editor\nIcon=editor-icon\nStartupWMClass=MyEditor\n[Desktop Action New]\nName=New Window\n",
        )?;
        let _xdg_dirs = ScopedEnvVar::set("XDG_DATA_DIRS", data_dir.path());
        let _xdg_home = ScopedEnvVar::set("XDG_DATA_HOME", data_dir.path().join("empty-home"));

        let resolver = DesktopResolver::load();
        assert_eq!(
            resolver.resolve("myeditor"),
            ("Example Editor".to_owned(), "editor-icon".to_owned())
        );
        assert_eq!(
            resolver.resolve("org.example.editor"),
            ("Example Editor".to_owned(), "editor-icon".to_owned())
        );
        assert_eq!(
            resolver.resolve("unknown"),
            ("unknown".to_owned(), String::new())
        );
        Ok(())
    }

    #[test]
    fn build_summary_excludes_locked_and_excluded_classes_and_computes_week_and_apps()
    -> crate::Result<()> {
        let connection = test_db();
        // Monday 2026-06-08 through Thursday 2026-06-11
        insert_total(&connection, "2026-06-08", "kitty", 3);
        insert_total(&connection, "2026-06-10", "kitty", 4);
        insert_total(&connection, "2026-06-11", "kitty", 3);
        insert_total(&connection, "2026-06-11", "firefox", 1);
        insert_total(&connection, "2026-06-11", LOCKED_CLASS, 500);
        for excluded in EXCLUDED_CLASSES {
            insert_total(&connection, "2026-06-11", excluded, 250);
        }

        let resolver = DesktopResolver {
            entries: HashMap::from([(
                "kitty".to_owned(),
                ("Kitty".to_owned(), "kitty".to_owned()),
            )]),
        };
        let now = Local
            .with_ymd_and_hms(2026, 6, 11, 14, 0, 0)
            .single()
            .expect("valid local timestamp");
        let mut cache = MonthCache::default();

        let summary = build_summary(
            &connection,
            &resolver,
            "Quickshell",
            false,
            &now,
            &mut cache,
        )?;
        assert_eq!(summary.total, 4);
        assert_eq!(summary.yesterday, 4);
        assert_eq!(summary.average, 4);
        assert_eq!(summary.week_range, "Jun 8 - Jun 14");
        assert_eq!(summary.week.len(), 7);
        assert!(summary.week[3].is_target);
        assert_eq!(summary.current, "");
        assert_eq!(summary.apps.len(), 2);
        assert_eq!(summary.apps[0].name, "Kitty");
        assert!(matches!(summary.apps[0].percent, Percent::Tenths(750)));
        assert_eq!(summary.apps[1].name, "firefox");
        assert!(matches!(summary.apps[1].percent, Percent::Tenths(250)));

        let locked_summary =
            build_summary(&connection, &resolver, "kitty", true, &now, &mut cache)?;
        assert_eq!(locked_summary.current, "Locked");
        Ok(())
    }

    #[test]
    fn load_month_pads_monday_offset_handles_december_rollover_and_caches_past_days()
    -> crate::Result<()> {
        let connection = test_db();
        insert_total(&connection, "2026-12-01", "kitty", 120);
        insert_total(&connection, "2026-12-15", "kitty", 60);

        let dec15 = NaiveDate::from_ymd_opt(2026, 12, 15).expect("valid date");
        let mut cache = MonthCache::default();
        let first = load_month(&connection, dec15, 300, &mut cache)?;

        // 2026-12-01 is Tuesday -> 1 leading padding slot + 31 December days.
        assert_eq!(first.len(), 32);
        assert!(first[0].is_none());
        let day1 = first[1].as_ref().expect("Dec 1 entry");
        assert_eq!(day1.date, "2026-12-01");
        assert_eq!(day1.total, 120);
        assert!(!day1.is_target);
        let target = first[15].as_ref().expect("Dec 15 entry");
        assert_eq!(target.total, 300);
        assert!(target.is_target);

        // Mutating a past day on the same date reads from MonthCache rather than re-querying.
        insert_total(&connection, "2026-12-02", "kitty", 999);
        let cached = load_month(&connection, dec15, 450, &mut cache)?;
        assert_eq!(cached[2].as_ref().expect("Dec 2 entry").total, 0);
        assert_eq!(cached[15].as_ref().expect("Dec 15 entry").total, 450);

        let dec16 = NaiveDate::from_ymd_opt(2026, 12, 16).expect("valid date");
        let refreshed = load_month(&connection, dec16, 10, &mut cache)?;
        assert_eq!(refreshed[2].as_ref().expect("Dec 2 entry").total, 999);
        Ok(())
    }
}
