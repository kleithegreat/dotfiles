use crate::{hypr, paths, theme};
use chrono::{Datelike, Duration, Local, NaiveDate};
use rusqlite::{Connection, Transaction, params};
use serde::{Serialize, Serializer};
use std::{
    collections::{HashMap, HashSet},
    fs,
    io::{self, Read},
    os::unix::net::UnixStream,
    path::{Path, PathBuf},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    thread,
    time::{Duration as StdDuration, Instant},
};

const LOCKED_CLASS: &str = "__locked__";

pub fn run(shutdown: Arc<AtomicBool>) -> crate::Result<()> {
    let current_class = Arc::new(Mutex::new(get_active_class()));
    let listener_class = Arc::clone(&current_class);
    let listener_shutdown = Arc::clone(&shutdown);

    let listener = thread::Builder::new()
        .name("desktopctl-focus-socket".to_owned())
        .spawn(move || listen_for_focus(listener_class, listener_shutdown))?;

    let resolver = DesktopResolver::load();
    let mut connection = init_db()?;
    let mut next_tick = Instant::now() + StdDuration::from_secs(1);

    while !shutdown.load(Ordering::SeqCst) {
        let sleep_for = next_tick.saturating_duration_since(Instant::now());
        if !sleep_for.is_zero() {
            thread::sleep(sleep_for);
        }
        if shutdown.load(Ordering::SeqCst) {
            break;
        }

        let now = Local::now();
        let mut class_name = current_class
            .lock()
            .map(|class_name| class_name.clone())
            .unwrap_or_default();
        let locked = is_screen_locked();

        if !locked {
            let reseeded_class = refresh_unlocked_class_name(class_name.clone(), get_active_class);
            if reseeded_class != class_name {
                set_current_class(&current_class, reseeded_class.clone());
                class_name = reseeded_class;
            }
        }

        if locked {
            accumulate(&mut connection, LOCKED_CLASS, &now)?;
        } else if !class_name.is_empty() {
            accumulate(&mut connection, &class_name, &now)?;
        }

        write_summary(&connection, &resolver, &class_name, locked, &now)?;

        next_tick += StdDuration::from_secs(1);
        if next_tick <= Instant::now() {
            next_tick = Instant::now() + StdDuration::from_secs(1);
        }
    }

    shutdown.store(true, Ordering::SeqCst);
    let _ = listener.join();

    Ok(())
}

fn init_db() -> crate::Result<Connection> {
    let db_path = paths::db_path()?;
    let mut connection = Connection::open(&db_path)?;
    connection.execute_batch(
        "
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS daily_totals (
            date      TEXT NOT NULL,
            app_class TEXT NOT NULL,
            seconds   INTEGER NOT NULL DEFAULT 0,
            PRIMARY KEY (date, app_class)
        );
        ",
    )?;

    if focus_tables_are_empty(&connection)? {
        migrate_legacy_focus_data(&mut connection, &db_path)?;
    }

    Ok(connection)
}

fn legacy_db_path() -> io::Result<PathBuf> {
    Ok(paths::xdg_data_home()?.join("focustime/focustime.db"))
}

fn focus_tables_are_empty(connection: &Connection) -> crate::Result<bool> {
    let row_count = connection.query_row(
        "
        SELECT COUNT(*) FROM daily_totals
        ",
        [],
        |row| row.get::<_, i64>(0),
    )?;
    Ok(row_count == 0)
}

fn migrate_legacy_focus_data(connection: &mut Connection, db_path: &Path) -> crate::Result<()> {
    let legacy_db_path = legacy_db_path()?;
    if !legacy_db_path.is_file() {
        return Ok(());
    }

    let legacy = Connection::open(&legacy_db_path)?;
    if !legacy_focus_has_rows(&legacy)? {
        return Ok(());
    }

    let transaction = connection.transaction()?;
    copy_daily_totals(&legacy, &transaction)?;
    transaction.commit()?;

    let legacy_dir = legacy_db_path
        .parent()
        .unwrap_or_else(|| Path::new("."))
        .display()
        .to_string();
    eprintln!(
        "Imported focus tracking data from {} into {}. You can delete {}.",
        legacy_db_path.display(),
        db_path.display(),
        legacy_dir
    );

    Ok(())
}

fn legacy_focus_has_rows(connection: &Connection) -> crate::Result<bool> {
    let table_count = connection.query_row(
        "
        SELECT COUNT(*)
        FROM sqlite_master
        WHERE type = 'table' AND name = 'daily_totals'
        ",
        [],
        |row| row.get::<_, i64>(0),
    )?;
    if table_count != 1 {
        return Ok(false);
    }

    focus_tables_are_empty(connection).map(|empty| !empty)
}

fn copy_daily_totals(legacy: &Connection, transaction: &Transaction<'_>) -> crate::Result<()> {
    let mut select = legacy.prepare("SELECT date, app_class, seconds FROM daily_totals")?;
    let rows = select.query_map([], |row| {
        Ok((
            row.get::<_, String>(0)?,
            row.get::<_, String>(1)?,
            row.get::<_, i64>(2)?,
        ))
    })?;

    let mut insert = transaction
        .prepare("INSERT INTO daily_totals (date, app_class, seconds) VALUES (?, ?, ?)")?;
    for row in rows {
        let (date, app_class, seconds) = row?;
        insert.execute(params![date, app_class, seconds])?;
    }

    Ok(())
}

fn accumulate(
    connection: &mut Connection,
    app_class: &str,
    now: &chrono::DateTime<Local>,
) -> crate::Result<()> {
    let date = now.format("%Y-%m-%d").to_string();
    let transaction = connection.transaction()?;

    transaction.execute(
        "INSERT INTO daily_totals (date, app_class, seconds) VALUES (?, ?, 1)
         ON CONFLICT(date, app_class) DO UPDATE SET seconds = seconds + 1",
        params![date, app_class],
    )?;
    transaction.commit()?;

    Ok(())
}

fn write_summary(
    connection: &Connection,
    resolver: &DesktopResolver,
    current_class: &str,
    locked: bool,
    now: &chrono::DateTime<Local>,
) -> crate::Result<()> {
    let summary = build_summary(connection, resolver, current_class, locked, now)?;
    let state_path = state_path()?;
    let temp_path = tmp_state_path(&state_path);
    fs::write(&temp_path, theme::json::to_python_string(&summary)?)?;
    fs::rename(temp_path, state_path)?;
    Ok(())
}

fn build_summary(
    connection: &Connection,
    resolver: &DesktopResolver,
    current_class: &str,
    locked: bool,
    now: &chrono::DateTime<Local>,
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
        round_half_even_i64(
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
    } else if current_class.is_empty() || excluded_classes().contains(current_class) {
        String::new()
    } else {
        resolver.resolve(current_class).0
    };

    let month = load_month(connection, today)?;

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
    let rows = statement.query_map(
        params![
            range_start.format("%Y-%m-%d").to_string(),
            range_end.format("%Y-%m-%d").to_string(),
            LOCKED_CLASS,
            "Desktop",
            "Quickshell",
            "",
        ],
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
    let excluded = excluded_classes();
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
        if excluded.contains(class_name.as_str()) {
            continue;
        }

        let (name, icon) = resolver.resolve(&class_name);
        apps.push(AppEntry {
            class_name,
            name,
            icon,
            seconds,
            percent: if total > 0 {
                Percent::Tenths(round_half_even_i64(seconds * 1000, total))
            } else {
                Percent::Integer(0)
            },
        });
    }

    Ok(apps)
}

fn load_month(connection: &Connection, today: NaiveDate) -> crate::Result<Vec<Option<MonthEntry>>> {
    let month_prefix = today.format("%Y-%m-").to_string();
    let mut statement = connection.prepare(
        "SELECT date, SUM(seconds)
         FROM daily_totals
         WHERE date LIKE ? AND app_class NOT IN (?, ?, ?, ?)
         GROUP BY date",
    )?;
    let rows = statement.query_map(
        params![
            format!("{month_prefix}%"),
            LOCKED_CLASS,
            "Desktop",
            "Quickshell",
            ""
        ],
        |row| Ok((row.get::<_, String>(0)?, row.get::<_, i64>(1)?)),
    )?;

    let mut month_sums = HashMap::new();
    for row in rows {
        let (date, total) = row?;
        month_sums.insert(date, total);
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
        month.push(Some(MonthEntry {
            date: date_string.clone(),
            total: *month_sums.get(&date_string).unwrap_or(&0),
            is_target: date == today,
        }));
    }

    Ok(month)
}

fn state_path() -> io::Result<PathBuf> {
    Ok(paths::xdg_runtime_dir()?.join("focustime_state.json"))
}

fn tmp_state_path(state_path: &Path) -> PathBuf {
    let mut path = state_path.to_path_buf();
    path.set_extension("tmp");
    path
}

fn is_screen_locked() -> bool {
    std::process::Command::new("pgrep")
        .args(["-x", "hyprlock"])
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
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

fn refresh_unlocked_class_name(current_class: String, seed: impl FnOnce() -> String) -> String {
    if !current_class.is_empty() {
        return current_class;
    }

    let reseeded_class = seed();
    if reseeded_class.is_empty() {
        current_class
    } else {
        reseeded_class
    }
}

fn listen_for_focus(current_class: Arc<Mutex<String>>, shutdown: Arc<AtomicBool>) {
    while !shutdown.load(Ordering::SeqCst) {
        let socket_path = match hypr::socket2_path() {
            Ok(path) => path,
            Err(_) => {
                if !shutdown.load(Ordering::SeqCst) {
                    thread::sleep(StdDuration::from_secs(2));
                }
                continue;
            }
        };

        if let Ok(mut socket) = UnixStream::connect(&socket_path) {
            set_current_class(&current_class, get_active_class());
            let _ = socket.set_read_timeout(Some(StdDuration::from_secs(5)));
            let mut buffer = Vec::new();
            let mut chunk = [0_u8; 4096];

            while !shutdown.load(Ordering::SeqCst) {
                match socket.read(&mut chunk) {
                    Ok(0) => break,
                    Ok(bytes_read) => {
                        buffer.extend_from_slice(&chunk[..bytes_read]);
                        consume_socket_lines(&mut buffer, &current_class);
                    }
                    Err(error)
                        if error.kind() == io::ErrorKind::WouldBlock
                            || error.kind() == io::ErrorKind::TimedOut =>
                    {
                        continue;
                    }
                    Err(_) => break,
                }
            }
        }

        if !shutdown.load(Ordering::SeqCst) {
            thread::sleep(StdDuration::from_secs(2));
        }
    }
}

fn consume_socket_lines(buffer: &mut Vec<u8>, current_class: &Arc<Mutex<String>>) {
    while let Some(newline_index) = buffer.iter().position(|byte| *byte == b'\n') {
        let line = buffer[..newline_index].to_vec();
        buffer.drain(..=newline_index);
        let text = String::from_utf8_lossy(&line);
        if let Some(rest) = text.strip_prefix("activewindow>>") {
            let class_name = rest
                .split_once(',')
                .map(|(class_name, _)| class_name)
                .unwrap_or(rest);
            set_current_class(current_class, class_name.to_owned());
        }
    }
}

fn set_current_class(current_class: &Arc<Mutex<String>>, class_name: String) {
    if let Ok(mut shared) = current_class.lock() {
        *shared = class_name;
    }
}

fn excluded_classes() -> HashSet<&'static str> {
    HashSet::from(["", "Desktop", "Quickshell"])
}

fn round_half_even_i64(numerator: i64, denominator: i64) -> i64 {
    if denominator == 0 {
        return 0;
    }

    let quotient = numerator / denominator;
    let remainder = numerator % denominator;
    let doubled = remainder.abs() * 2;
    let denominator_abs = denominator.abs();

    if doubled < denominator_abs {
        quotient
    } else if doubled > denominator_abs {
        quotient + signum(numerator, denominator)
    } else if quotient % 2 == 0 {
        quotient
    } else {
        quotient + signum(numerator, denominator)
    }
}

fn signum(numerator: i64, denominator: i64) -> i64 {
    if (numerator >= 0) == (denominator >= 0) {
        1
    } else {
        -1
    }
}

#[cfg(test)]
mod tests {
    use super::{AppEntry, MonthEntry, Percent, Summary, WeekEntry, refresh_unlocked_class_name};

    #[test]
    fn summary_serialization_matches_the_python_style_runtime_contract() {
        // The summary JSON is a byte-level contract with the Quickshell
        // consumer; keep this in lockstep with theme::json::to_python_string.
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

        let rendered =
            crate::theme::json::to_python_string(&summary).expect("summary should serialize");

        assert_eq!(
            rendered,
            "{\"last_updated\": 1765000000, \"total\": 3600, \
             \"average\": 1800, \"week_range\": \"Jun 8 - Jun 14\", \"yesterday\": 1200, \
             \"current\": \"Caf\\u00e9\", \"apps\": [{\"class\": \"kitty\", \"name\": \"kitty\", \
             \"icon\": \"kitty-icon\", \"seconds\": 3000, \"percent\": 83.3}, \
             {\"class\": \"caf\\u00e9\", \"name\": \"Caf\\u00e9\", \"icon\": \"\", \
             \"seconds\": 600, \"percent\": 0}], \"week\": [{\"date\": \"2026-06-08\", \
             \"day\": \"Mon\", \"total\": 0, \"is_target\": false}], \"month\": [null, \
             {\"date\": \"2026-06-01\", \"total\": 42, \"is_target\": true}]}"
        );
    }

    #[test]
    fn percent_tenths_serialize_with_one_decimal_digit() {
        let whole = crate::theme::json::to_python_string(&Percent::Tenths(1000))
            .expect("percent should serialize");
        let fractional = crate::theme::json::to_python_string(&Percent::Tenths(123))
            .expect("percent should serialize");
        let zero = crate::theme::json::to_python_string(&Percent::Tenths(0))
            .expect("percent should serialize");

        assert_eq!(whole, "100.0");
        assert_eq!(fractional, "12.3");
        assert_eq!(zero, "0.0");
    }

    #[test]
    fn refresh_unlocked_class_name_reseeds_empty_classes() {
        let class_name = refresh_unlocked_class_name(String::new(), || "firefox".to_owned());
        assert_eq!(class_name, "firefox");
    }

    #[test]
    fn refresh_unlocked_class_name_keeps_existing_classes() {
        let class_name = refresh_unlocked_class_name("kitty".to_owned(), || "firefox".to_owned());
        assert_eq!(class_name, "kitty");
    }

    #[test]
    fn refresh_unlocked_class_name_keeps_empty_when_reseed_is_empty() {
        let class_name = refresh_unlocked_class_name(String::new(), String::new);
        assert!(class_name.is_empty());
    }
}

struct DesktopResolver {
    entries: HashMap<String, (String, String)>,
}

impl DesktopResolver {
    fn load() -> Self {
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

    fn resolve(&self, window_class: &str) -> (String, String) {
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
            // Tenths must render with one decimal digit (e.g. 83.3, 100.0) to
            // keep the runtime JSON contract; ryu prints n/10.0 exactly so.
            Self::Integer(value) => serializer.serialize_i64(*value),
            Self::Tenths(value) => serializer.serialize_f64(*value as f64 / 10.0),
        }
    }
}
