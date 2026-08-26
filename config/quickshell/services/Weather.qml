pragma Singleton

import QtQuick
import Quickshell.Io

// Current conditions for wherever the sun schedule says we are.
QtObject {
    id: root

    property bool ready: false
    property bool loading: false
    property string error: ""

    property real temperature: 0
    property real high: 0
    property real low: 0
    property int humidity: 0
    property real wind: 0
    property int rainChance: 0
    property int code: -1
    property bool daylight: true
    property string place: ""
    property string sunrise: ""
    property string sunset: ""
    property string updated: ""

    property real _latitude: 0
    property real _longitude: 0
    property bool _located: false

    readonly property bool imperial: Qt.locale().measurementSystem !== Locale.MetricSystem
    readonly property string unit: imperial ? "°F" : "°C"
    readonly property string windUnit: imperial ? "mph" : "km/h"

    // WMO 4677, collapsed to the distinctions a glanceable summary can carry.
    readonly property string conditions: {
        if (code < 0)
            return "";
        if (code === 0)
            return daylight ? "Clear" : "Clear night";
        if (code <= 2)
            return "Partly cloudy";
        if (code === 3)
            return "Overcast";
        if (code === 45 || code === 48)
            return "Fog";
        if (code <= 57)
            return "Drizzle";
        if (code <= 67)
            return "Rain";
        if (code <= 77)
            return "Snow";
        if (code <= 82)
            return "Showers";
        if (code <= 86)
            return "Snow showers";
        return "Thunderstorm";
    }

    function refresh(force) {
        if (loading)
            return;
        if (ready && !force && Date.now() - _fetchedAt < 900000)
            return;

        loading = true;
        error = "";
        if (_located)
            _fetch();
        else
            sun.running = true;
    }

    property real _fetchedAt: 0

    function _fetch() {
        if (!_located) {
            loading = false;
            error = "Location unavailable";
            return;
        }

        const url = "https://api.open-meteo.com/v1/forecast" + "?latitude=" + _latitude.toFixed(4) + "&longitude=" + _longitude.toFixed(4) + "&current=temperature_2m,relative_humidity_2m,is_day,weather_code,wind_speed_10m" + "&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max" + "&forecast_days=1&timezone=auto" + (imperial ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "");

        forecast.command = ["curl", "-fsS", "--connect-timeout", "4", "--max-time", "8", url];
        forecast.running = true;
    }

    // `desktopctl sun status` can take several seconds on a cold geolocation
    // lookup, so it is never on a startup path — only on first open.
    readonly property Process _sun: Process {
        id: sun
        command: ["desktopctl", "sun", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const coords = this.text.match(/Location:\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)/);
                const named = this.text.match(/Place:\s*(.+)/);
                const solar = this.text.match(/Sunrise:\s+([\d:]+)\s+Sunset:\s+([\d:]+)/);
                if (named)
                    root.place = named[1].trim();
                if (coords) {
                    root._latitude = parseFloat(coords[1]);
                    root._longitude = parseFloat(coords[2]);
                    root._located = true;
                }
                if (solar) {
                    root.sunrise = solar[1];
                    root.sunset = solar[2];
                }
                root._fetch();
            }
        }
        onExited: code => {
            if (code !== 0 && !root._located) {
                root.loading = false;
                root.error = "Location unavailable";
            }
        }
    }

    readonly property Process _forecast: Process {
        id: forecast
        stdout: StdioCollector {
            onStreamFinished: {
                root.loading = false;
                try {
                    const data = JSON.parse(this.text);
                    const now = data.current;
                    const day = data.daily;

                    root.temperature = now.temperature_2m;
                    root.humidity = now.relative_humidity_2m;
                    root.wind = now.wind_speed_10m;
                    root.code = now.weather_code;
                    root.daylight = now.is_day === 1;
                    root.high = day.temperature_2m_max[0];
                    root.low = day.temperature_2m_min[0];
                    root.rainChance = day.precipitation_probability_max[0] || 0;
                    root.updated = Qt.formatDateTime(new Date(), "h:mm AP");
                    root._fetchedAt = Date.now();
                    root.ready = true;
                    root.error = "";
                } catch (e) {
                    root.error = "Forecast unavailable";
                }
            }
        }
        onExited: code => {
            root.loading = false;
            if (code !== 0)
                root.error = "Forecast unavailable";
        }
    }
}
