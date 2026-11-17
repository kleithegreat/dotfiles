//! The last 24 hours, as the Power pane draws them: battery level in 15-minute
//! bars from UPower's charge history, and draw and app energy from the samples.

use crate::daemon::focus::DesktopResolver;
use rusqlite::{Connection, params};
use serde::Serialize;

const DAY: i64 = 24 * 3600;
const LEVEL_BARS: i64 = 96;
const APPS: usize = 8;

/// UPower states that mean the charger is connected: charging, fully charged,
/// and held by the charge limit.
const PLUGGED_STATES: [u32; 3] = [1, 4, 5];

#[zbus::proxy(
    interface = "org.freedesktop.UPower.Device",
    default_service = "org.freedesktop.UPower"
)]
pub(super) trait UPowerDevice {
    fn get_history(
        &self,
        kind: &str,
        timespan: u32,
        resolution: u32,
    ) -> zbus::Result<Vec<(u32, f64, u32)>>;
}

pub(super) async fn upower_device(battery: &str) -> zbus::Result<UPowerDeviceProxy<'static>> {
    UPowerDeviceProxy::builder(&zbus::Connection::system().await?)
        .path(format!("/org/freedesktop/UPower/devices/battery_{battery}"))
        .build()
        .await
}

/// UPower's charge points for the last day: `(unix time, percent, state)`.
pub(super) async fn charge_points(device: &UPowerDeviceProxy<'_>) -> Vec<(u32, f64, u32)> {
    device
        .get_history("charge", DAY as u32, 1000)
        .await
        .unwrap_or_default()
}

#[derive(Serialize)]
pub(super) struct Summary {
    /// Unix time the window opens: the hour 24 hours before the current one ends.
    start: i64,
    levels: Vec<Option<Level>>,
    hours: Vec<Hour>,
    apps: Vec<App>,
    average_w: Option<f64>,
}

#[derive(Debug, PartialEq, Serialize)]
struct Level {
    percent: f64,
    plugged: bool,
}

#[derive(Serialize)]
struct Hour {
    watts: Option<f64>,
    minutes: f64,
}

#[derive(Serialize)]
struct App {
    name: String,
    wh: f64,
    percent: f64,
}

pub(super) fn summary(
    connection: &Connection,
    resolver: &DesktopResolver,
    points: &[(u32, f64, u32)],
    now: i64,
) -> crate::Result<Summary> {
    let start = (now / 3600 + 1) * 3600 - DAY;

    let mut hours: Vec<Hour> = (0..24)
        .map(|_| Hour {
            watts: None,
            minutes: 0.0,
        })
        .collect();
    let mut joules = 0.0;
    let mut seconds = 0.0;
    let mut statement = connection.prepare_cached(
        "SELECT (ts - ?1) / 3600, SUM(battery_w * seconds), SUM(seconds)
         FROM power_samples WHERE ts >= ?1 GROUP BY 1",
    )?;
    for row in statement.query_map(params![start], |row| {
        Ok((
            row.get::<_, i64>(0)?,
            row.get::<_, f64>(1)?,
            row.get::<_, f64>(2)?,
        ))
    })? {
        let (hour, hour_joules, hour_seconds) = row?;
        if let Some(slot) = usize::try_from(hour)
            .ok()
            .and_then(|hour| hours.get_mut(hour))
        {
            *slot = Hour {
                watts: Some(hour_joules / hour_seconds),
                minutes: hour_seconds / 60.0,
            };
        }
        joules += hour_joules;
        seconds += hour_seconds;
    }

    let mut statement = connection.prepare_cached(
        "SELECT p.name, SUM((COALESCE(p.cpu_w, 0) + COALESCE(p.gpu_w, 0)) * s.seconds)
         FROM power_samples s JOIN power_processes p ON p.sample = s.id
         WHERE s.ts >= ?1 GROUP BY p.name ORDER BY 2 DESC LIMIT ?2",
    )?;
    let apps = statement
        .query_map(params![start, APPS], |row| {
            Ok((row.get::<_, String>(0)?, row.get::<_, f64>(1)?))
        })?
        .map(|row| {
            let (name, app_joules) = row?;
            Ok(App {
                name: resolver.resolve(&name).0,
                wh: app_joules / 3600.0,
                percent: if joules > 0.0 {
                    app_joules / joules * 100.0
                } else {
                    0.0
                },
            })
        })
        .collect::<crate::Result<_>>()?;

    Ok(Summary {
        start,
        levels: levels(points, start, now),
        hours,
        apps,
        average_w: (seconds > 0.0).then(|| joules / seconds),
    })
}

/// Each bar holds the last point before it closes. UPower writes a 0% point of
/// unknown state when it starts, so the bars after a boot stay empty until a
/// real reading arrives.
fn levels(points: &[(u32, f64, u32)], start: i64, now: i64) -> Vec<Option<Level>> {
    let mut points = points.to_vec();
    points.sort_by_key(|(time, _, _)| *time);
    let width = DAY / LEVEL_BARS;
    (0..LEVEL_BARS)
        .map(|bar| {
            let opens = start + bar * width;
            if opens > now {
                return None;
            }
            let closes = (opens + width).min(now + 1);
            let (_, percent, state) = points
                .iter()
                .take_while(|(time, _, _)| i64::from(*time) < closes)
                .last()?;
            (*percent > 0.0).then(|| Level {
                percent: *percent,
                plugged: PLUGGED_STATES.contains(state),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn level_bars_carry_the_last_point_forward_and_stop_at_now() {
        let start = 1_000_000;
        let quarter = 900;
        let points = [
            ((start + quarter + 10) as u32, 80.0, 2),
            ((start + 3 * quarter + 10) as u32, 0.0, 0),
            ((start + 5 * quarter + 10) as u32, 70.0, 1),
        ];
        let bars = levels(&points, start, start + 6 * quarter + 1);
        let discharging = Some(Level {
            percent: 80.0,
            plugged: false,
        });
        let charging = Some(Level {
            percent: 70.0,
            plugged: true,
        });
        assert_eq!(bars.len(), 96);
        assert_eq!(bars[0], None);
        assert_eq!(bars[1], discharging);
        assert_eq!(bars[2], discharging);
        assert_eq!(bars[3], None);
        assert_eq!(bars[5], charging);
        assert_eq!(bars[6], charging);
        assert_eq!(bars[7], None);
    }
}
