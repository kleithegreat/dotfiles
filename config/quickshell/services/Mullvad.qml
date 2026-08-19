pragma Singleton

import QtQuick
import Quickshell.Io

QtObject {
    id: root

    // disconnected · connecting · connected · disconnecting · error
    property string state: "disconnected"
    property string country: ""
    property string city: ""
    property string ip: ""
    property string pending: ""

    property string selectedCountry: ""
    property string selectedCity: ""
    property string selectedHostname: ""

    // [{ code, name, cities: [{ code, name }] }]
    property var relays: []
    property bool relaysLoaded: false

    readonly property bool connected: state === "connected"
    readonly property bool busy: pending !== "" || command.running
    readonly property bool loadingRelays: relayList.running

    readonly property string location: {
        if (city !== "" && country !== "")
            return city + ", " + country;
        return country;
    }

    readonly property string selectedLabel: {
        if (selectedHostname !== "")
            return selectedHostname;

        const place = _lookup(selectedCountry, selectedCity);
        if (place.city !== "")
            return place.city + ", " + place.country;
        if (place.country !== "")
            return place.country;
        return "Automatic";
    }

    function _lookup(countryCode, cityCode) {
        for (let i = 0; i < relays.length; i++) {
            if (relays[i].code !== countryCode)
                continue;
            for (let j = 0; j < relays[i].cities.length; j++) {
                if (relays[i].cities[j].code === cityCode)
                    return { country: relays[i].name, city: relays[i].cities[j].name };
            }
            return { country: relays[i].name, city: "" };
        }
        return { country: countryCode, city: "" };
    }

    function refresh() {
        if (!status.running)
            status.running = true;
        if (!selection.running)
            selection.running = true;
    }

    function loadRelays() {
        if (relaysLoaded || relayList.running)
            return;
        relayList.running = true;
    }

    function set(enabled) {
        if (busy)
            return;
        pending = enabled ? "connect" : "disconnect";
        state = enabled ? "connecting" : "disconnecting";
        command.command = ["mullvad", enabled ? "connect" : "disconnect"];
        command.running = true;
    }

    function toggle() {
        set(!connected);
    }

    function setLocation(countryCode, cityCode) {
        if (command.running)
            return;
        selectedCountry = countryCode;
        selectedCity = cityCode || "";
        selectedHostname = "";
        command.command = cityCode ? ["mullvad", "relay", "set", "location", countryCode, cityCode] : ["mullvad", "relay", "set", "location", countryCode];
        command.running = true;
    }

    Component.onCompleted: refresh()

    readonly property Process _status: Process {
        id: status
        command: ["mullvad", "status", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(this.text);
                    root.state = data.state || "disconnected";
                    const place = (data.details && data.details.location) || {};
                    root.country = place.country || "";
                    root.city = place.city || "";
                    root.ip = place.ipv4 || "";
                    root.pending = "";
                } catch (e) {
                    root.state = "error";
                }
            }
        }
    }

    readonly property Process _selection: Process {
        id: selection
        command: ["mullvad", "relay", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                const hostname = this.text.match(/hostname\s+(\S+)/);
                const place = this.text.match(/country\s+([a-z]{2})(?:\s+city\s+(\S+))?/);
                root.selectedHostname = hostname ? hostname[1] : "";
                root.selectedCountry = place ? place[1] : "";
                root.selectedCity = place && place[2] ? place[2] : "";
            }
        }
    }

    // Tab depth is the tree level: country, then city, then relay hostnames we
    // do not enumerate.
    readonly property Process _relayList: Process {
        id: relayList
        command: ["mullvad", "relay", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const countries = [];
                const lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    if (line.trim() === "")
                        continue;

                    if (line[0] !== "\t") {
                        const match = line.match(/^(.*)\s+\(([a-z]{2})\)\s*$/);
                        if (match)
                            countries.push({ code: match[2], name: match[1].trim(), cities: [] });
                    } else if (line[1] !== "\t" && countries.length > 0) {
                        const match = line.trim().match(/^(.*?)\s+\(([a-z]{3})\)/);
                        if (match)
                            countries[countries.length - 1].cities.push({ code: match[2], name: match[1].trim() });
                    }
                }
                root.relays = countries;
                root.relaysLoaded = countries.length > 0;
            }
        }
    }

    readonly property Process _command: Process {
        id: command
        stderr: StdioCollector {
            id: failure
        }
        onExited: code => {
            root.pending = "";
            if (code !== 0)
                Toast.error(failure.text.trim().split("\n").filter(line => line !== "").pop() || "Mullvad command failed");
            root.refresh();
        }
    }

    readonly property Timer _poll: Timer {
        interval: root.busy ? 2000 : 15000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
