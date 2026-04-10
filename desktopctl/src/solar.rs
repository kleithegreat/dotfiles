use crate::paths;
use chrono::{DateTime, Datelike, Days, Duration, Local, LocalResult, NaiveDate, TimeZone, Utc};
use serde::{Deserialize, Serialize};
use std::{fs, io, process::Command};

pub const DEFAULT_LATITUDE: f64 = 30.6280;
pub const DEFAULT_LONGITUDE: f64 = -96.3344;
pub const HYPRSUNSET_TEMP: i32 = 4500;
pub const DARK_ON_HOUR: u32 = 23;

#[derive(Debug, Clone, Copy)]
pub struct Coordinates {
    pub latitude: f64,
    pub longitude: f64,
}

#[derive(Debug, Clone)]
pub struct SolarEvent {
    pub when: DateTime<Local>,
}

#[derive(Debug, Clone)]
pub struct SolarStatus {
    pub location: Coordinates,
    pub sunrise: DateTime<Local>,
    pub sunset: DateTime<Local>,
    pub is_night: bool,
    pub is_dark: bool,
    pub next_sunrise: DateTime<Local>,
    pub next_sunset: DateTime<Local>,
    pub next_dark_on: DateTime<Local>,
}

#[derive(Debug, Deserialize, Serialize)]
struct CachedLocation {
    latitude: f64,
    longitude: f64,
}

pub fn print_status() -> crate::Result<()> {
    let location = resolve_location()?;
    let status = status_for_now(Local::now(), location);

    println!(
        "Location: {:.4}, {:.4}",
        status.location.latitude, status.location.longitude
    );
    println!(
        "Sunrise:  {}  Sunset: {}",
        status.sunrise.format("%H:%M"),
        status.sunset.format("%H:%M")
    );
    println!(
        "State:    night={}  dark_hint={}",
        status.is_night, status.is_dark
    );
    println!(
        "Next:     sunrise={}  sunset={}  dark_on={}",
        status.next_sunrise.format("%m-%d %H:%M"),
        status.next_sunset.format("%m-%d %H:%M"),
        status.next_dark_on.format("%m-%d %H:%M")
    );

    Ok(())
}

pub fn resolve_location() -> io::Result<Coordinates> {
    let cache_path = paths::xdg_cache_home()?.join("sun-schedule/location.json");

    if let Some(location) = read_cached_location(&cache_path) {
        return Ok(location);
    }

    if let Some(location) = query_geoclue() {
        if let Some(parent) = cache_path.parent() {
            let _ = fs::create_dir_all(parent);
        }
        let payload = CachedLocation {
            latitude: location.latitude,
            longitude: location.longitude,
        };
        if let Ok(json) = serde_json::to_vec(&payload) {
            let _ = fs::write(&cache_path, json);
        }

        return Ok(location);
    }

    Ok(Coordinates {
        latitude: DEFAULT_LATITUDE,
        longitude: DEFAULT_LONGITUDE,
    })
}

pub fn status_for_now(now: DateTime<Local>, location: Coordinates) -> SolarStatus {
    let today = now.date_naive();
    let tomorrow = today
        .checked_add_days(Days::new(1))
        .expect("valid tomorrow");

    let (sunrise_utc, sunset_utc) = sun_times(location.latitude, location.longitude, today);
    let (sunrise_next_utc, sunset_next_utc) =
        sun_times(location.latitude, location.longitude, tomorrow);

    let sunrise = sunrise_utc.with_timezone(&Local);
    let sunset = sunset_utc.with_timezone(&Local);
    let sunrise_next = sunrise_next_utc.with_timezone(&Local);
    let sunset_next = sunset_next_utc.with_timezone(&Local);

    let dark_on_today = local_datetime(today, DARK_ON_HOUR, 0, 0);
    let next_dark_on = if dark_on_today > now {
        dark_on_today
    } else {
        dark_on_today + Duration::days(1)
    };

    let next_sunrise = if sunrise > now { sunrise } else { sunrise_next };
    let next_sunset = if sunset > now { sunset } else { sunset_next };

    SolarStatus {
        location,
        sunrise,
        sunset,
        is_night: now < sunrise || now >= sunset,
        is_dark: now >= dark_on_today || now < sunrise,
        next_sunrise,
        next_sunset,
        next_dark_on,
    }
}

pub fn next_event(status: &SolarStatus) -> SolarEvent {
    let mut next = SolarEvent {
        when: status.next_sunrise,
    };

    if status.next_sunset < next.when {
        next = SolarEvent {
            when: status.next_sunset,
        };
    }
    if status.next_dark_on < next.when {
        next = SolarEvent {
            when: status.next_dark_on,
        };
    }

    next
}

pub fn sun_times(latitude: f64, longitude: f64, date: NaiveDate) -> (DateTime<Utc>, DateTime<Utc>) {
    let day_of_year = f64::from(date.ordinal() as u16);
    let lng_hour = longitude / 15.0;

    let compute = |rising: bool| -> f64 {
        let base_hour = if rising { 6.0 } else { 18.0 };
        let t = day_of_year + (base_hour - lng_hour) / 24.0;
        let mean_anomaly = 0.9856 * t - 3.289;
        let true_longitude = (mean_anomaly
            + 1.916 * mean_anomaly.to_radians().sin()
            + 0.020 * (2.0 * mean_anomaly).to_radians().sin()
            + 282.634)
            .rem_euclid(360.0);

        let mut right_ascension = (0.91764 * true_longitude.to_radians().tan())
            .atan()
            .to_degrees();
        right_ascension +=
            (true_longitude / 90.0).floor() * 90.0 - (right_ascension / 90.0).floor() * 90.0;
        right_ascension /= 15.0;

        let sin_declination = 0.39782 * true_longitude.to_radians().sin();
        let cos_declination = sin_declination.asin().cos();
        let latitude_radians = latitude.to_radians();
        let mut cos_hour_angle = (90.833_f64.to_radians().cos()
            - sin_declination * latitude_radians.sin())
            / (cos_declination * latitude_radians.cos());
        cos_hour_angle = cos_hour_angle.clamp(-1.0, 1.0);

        let hour_angle_degrees = cos_hour_angle.acos().to_degrees();
        let hour_angle = if rising {
            (360.0 - hour_angle_degrees) / 15.0
        } else {
            hour_angle_degrees / 15.0
        };

        let local_mean_time = hour_angle + right_ascension - 0.06571 * t - 6.622;
        (local_mean_time - lng_hour).rem_euclid(24.0)
    };

    let base = Utc
        .with_ymd_and_hms(date.year(), date.month(), date.day(), 0, 0, 0)
        .single()
        .expect("valid UTC date");
    let sunrise = base + duration_from_hours(compute(true));
    let mut sunset = base + duration_from_hours(compute(false));
    if sunset < sunrise {
        sunset += Duration::days(1);
    }

    (sunrise, sunset)
}

fn read_cached_location(path: &std::path::Path) -> Option<Coordinates> {
    let contents = fs::read(path).ok()?;
    let cached: CachedLocation = serde_json::from_slice(&contents).ok()?;
    Some(Coordinates {
        latitude: cached.latitude,
        longitude: cached.longitude,
    })
}

fn query_geoclue() -> Option<Coordinates> {
    let output = Command::new("timeout")
        .args(["10", "where-am-i"])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut latitude = None;
    let mut longitude = None;

    for line in stdout.lines() {
        let lower = line.to_ascii_lowercase();
        if lower.contains("latitude") {
            latitude = parse_coordinate_line(line);
        } else if lower.contains("longitude") {
            longitude = parse_coordinate_line(line);
        }
    }

    Some(Coordinates {
        latitude: latitude?,
        longitude: longitude?,
    })
}

fn parse_coordinate_line(line: &str) -> Option<f64> {
    line.split(':')
        .next_back()?
        .trim()
        .trim_end_matches('\u{00b0}')
        .parse()
        .ok()
}

fn local_datetime(date: NaiveDate, hour: u32, minute: u32, second: u32) -> DateTime<Local> {
    match Local.with_ymd_and_hms(date.year(), date.month(), date.day(), hour, minute, second) {
        LocalResult::Single(dt) => dt,
        LocalResult::Ambiguous(dt, _) => dt,
        LocalResult::None => Local
            .from_utc_datetime(
                &date
                    .and_hms_opt(hour, minute, second)
                    .expect("valid local time fallback"),
            )
            .with_timezone(&Local),
    }
}

fn duration_from_hours(hours: f64) -> Duration {
    Duration::microseconds((hours * 3_600_000_000.0).round() as i64)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{ScopedEnvVar, TempDir, env_lock};

    fn sample_location() -> Coordinates {
        Coordinates {
            latitude: DEFAULT_LATITUDE,
            longitude: DEFAULT_LONGITUDE,
        }
    }

    #[test]
    fn sun_times_return_a_same_day_sunrise_and_later_sunset() {
        let date = NaiveDate::from_ymd_opt(2026, 4, 10).expect("valid date");
        let (sunrise, sunset) = sun_times(DEFAULT_LATITUDE, DEFAULT_LONGITUDE, date);

        assert_eq!(sunrise.date_naive(), date);
        assert!(sunset > sunrise);
        assert!(sunset - sunrise > Duration::hours(6));
    }

    #[test]
    fn status_for_now_before_sunrise_is_night_and_dark() {
        let location = sample_location();
        let date = NaiveDate::from_ymd_opt(2026, 4, 10).expect("valid date");
        let (sunrise_utc, _) = sun_times(location.latitude, location.longitude, date);
        let sunrise = sunrise_utc.with_timezone(&Local);
        let now = sunrise - Duration::minutes(30);

        let status = status_for_now(now, location);

        assert!(status.is_night);
        assert!(status.is_dark);
        assert_eq!(next_event(&status).when, sunrise);
    }

    #[test]
    fn status_for_now_after_sunset_waits_for_dark_hint_cutover() {
        let location = sample_location();
        let date = NaiveDate::from_ymd_opt(2026, 4, 10).expect("valid date");
        let (_, sunset_utc) = sun_times(location.latitude, location.longitude, date);
        let sunset = sunset_utc.with_timezone(&Local);
        let now = sunset + Duration::minutes(30);

        let status = status_for_now(now, location);
        let dark_on = local_datetime(date, DARK_ON_HOUR, 0, 0);

        assert!(status.is_night);
        assert!(!status.is_dark);
        assert_eq!(status.next_dark_on, dark_on);
        assert_eq!(next_event(&status).when, dark_on);
    }

    #[test]
    fn resolve_location_prefers_cached_coordinates() {
        let _lock = env_lock();
        let temp_dir = TempDir::new("desktopctl-solar-cache").expect("temp dir");
        let _cache_home = ScopedEnvVar::set("XDG_CACHE_HOME", temp_dir.path().as_os_str());
        let cache_path = temp_dir.path().join("sun-schedule/location.json");
        fs::create_dir_all(cache_path.parent().expect("cache parent")).expect("create cache dir");
        fs::write(&cache_path, r#"{"latitude":12.34,"longitude":56.78}"#).expect("write cache");

        let location = resolve_location().expect("location should resolve");

        assert!((location.latitude - 12.34).abs() < f64::EPSILON);
        assert!((location.longitude - 56.78).abs() < f64::EPSILON);
    }

    #[test]
    fn parse_coordinate_line_strips_degree_marker() {
        assert_eq!(parse_coordinate_line("Latitude: 30.6280°"), Some(30.628));
        assert_eq!(parse_coordinate_line("Longitude: -96.3344"), Some(-96.3344));
        assert_eq!(parse_coordinate_line("Latitude unavailable"), None);
    }
}
