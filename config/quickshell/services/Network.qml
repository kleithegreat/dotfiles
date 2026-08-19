pragma Singleton

import QtQuick
import Quickshell.Io

// Connectivity state and the writes that change it.
//
// The whole picture — radio, default route, active device, addresses, SSID,
// link — is read by *one* command that does its own joining in shell and emits
// tagged lines. The old service fanned four nmcli calls out and rebuilt the
// answer behind a hand-rolled barrier of "is every process idle yet"; every
// field it produced needed a staging twin to survive the wait. One read, one
// parse, one state update needs neither.
QtObject {
    id: root

    // ── State ──────────────────────────────────────────────────────────────

    property bool wifiRadio: false
    property bool radioKnown: false

    // wifi · ethernet · ""
    property string linkType: ""
    property string device: ""
    property string connectionName: ""
    property string connectionUuid: ""
    property string ssid: ""
    property int signal: 0
    property string ipAddress: ""
    property string gateway: ""
    property string dns: ""
    property string frequency: ""
    property string linkRate: ""
    property string ethernetSpeed: ""
    property string ethernetDuplex: ""
    property string connectivity: ""

    property string error: ""
    property string busy: ""

    readonly property bool online: linkType !== ""
    readonly property bool captivePortal: connectivity === "portal" || connectivity === "limited"
    readonly property bool scanning: scanner.running
    readonly property bool radioBusy: busy === "radio"

    readonly property string label: {
        if (linkType === "wifi")
            return ssid !== "" ? ssid : connectionName !== "" ? connectionName : "Wi-Fi";
        if (linkType === "ethernet")
            return connectionName !== "" ? connectionName : "Ethernet";
        return wifiRadio ? "Not connected" : "Wi-Fi off";
    }

    readonly property string icon: {
        if (linkType === "ethernet")
            return "ethernet";
        if (!wifiRadio)
            return "wifi-off";
        if (linkType !== "wifi")
            return "wifi-off";
        if (signal >= 75)
            return "wifi";
        if (signal >= 50)
            return "wifi-good";
        if (signal >= 25)
            return "wifi-fair";
        return "wifi-poor";
    }

    readonly property ListModel networks: ListModel {
        id: networks
    }

    readonly property ListModel known: ListModel {
        id: known
    }

    signal connectSucceeded
    signal connectFailed(string reason)

    // ── Reads ──────────────────────────────────────────────────────────────

    function refresh() {
        if (!state.running)
            state.running = true;
    }

    function scan() {
        if (!scanner.running)
            scanner.running = true;
        loadKnown();
    }

    function loadKnown() {
        if (!saved.running)
            saved.running = true;
    }

    // nmcli -t escapes field separators inside values; a network called
    // "a:b" must not split into two fields.
    function _split(line) {
        const fields = [];
        let current = "";
        for (let i = 0; i < line.length; i++) {
            const ch = line[i];
            if (ch === "\\" && i + 1 < line.length) {
                current += line[++i];
            } else if (ch === ":") {
                fields.push(current);
                current = "";
            } else {
                current += ch;
            }
        }
        fields.push(current);
        return fields;
    }

    function savedFor(name) {
        for (let i = 0; i < known.count; i++) {
            if (known.get(i).name === name)
                return known.get(i);
        }
        return null;
    }

    function isKnown(name) {
        return savedFor(name) !== null;
    }

    function isEnterprise(security) {
        return String(security).indexOf("802.1X") >= 0;
    }

    // ── Writes ─────────────────────────────────────────────────────────────

    function setWifiRadio(enabled) {
        if (busy !== "")
            return;
        if (radioKnown && wifiRadio === enabled)
            return;

        busy = "radio";
        wifiRadio = enabled;
        radioKnown = true;
        if (!enabled) {
            networks.clear();
            if (linkType === "wifi")
                _clearLink();
        }

        radio.command = ["nmcli", "radio", "wifi", enabled ? "on" : "off"];
        radio.running = true;
    }

    function toggleWifiRadio() {
        setWifiRadio(!wifiRadio);
    }

    // Returns what the caller must ask the user for: "" when the connection is
    // already under way, otherwise "password" or "enterprise".
    function connect(name, security) {
        error = "";

        if (isEnterprise(security))
            return "enterprise";

        const entry = savedFor(name);
        if (entry) {
            _run(["nmcli", "con", "up", "uuid", entry.uuid]);
            return "";
        }

        if (security !== "")
            return "password";

        _run(["nmcli", "dev", "wifi", "connect", name]);
        return "";
    }

    function connectWithPassword(name, password) {
        _run(["nmcli", "dev", "wifi", "connect", name, "password", password]);
    }

    function connectEnterprise(name, identity, password) {
        const entry = savedFor(name);
        _run(["bash", "-c", _enterpriseScript, "--", name, identity, password, entry ? entry.uuid : ""]);
    }

    function disconnect() {
        if (connectionUuid === "")
            return;
        busy = "disconnect";
        _run(["nmcli", "con", "down", "uuid", connectionUuid]);
    }

    function forget(name) {
        const entry = savedFor(name);
        if (!entry)
            return;
        busy = "forget";
        _run(["nmcli", "con", "delete", "uuid", entry.uuid]);
    }

    // "auto" restores DHCP-provided servers.
    function setDns(server) {
        if (connectionUuid === "")
            return;
        busy = "dns";
        _run(server === "auto" ? ["nmcli", "con", "mod", "uuid", connectionUuid, "ipv4.dns", "", "ipv4.ignore-auto-dns", "no"] : ["nmcli", "con", "mod", "uuid", connectionUuid, "ipv4.dns", server, "ipv4.ignore-auto-dns", "yes"]);
    }

    function openCaptivePortal() {
        portal.running = true;
    }

    function _run(command) {
        writer.command = command;
        writer.running = true;
    }

    function _clearLink() {
        linkType = "";
        device = "";
        connectionName = "";
        connectionUuid = "";
        ssid = "";
        signal = 0;
        ipAddress = "";
        gateway = "";
        dns = "";
        frequency = "";
        linkRate = "";
        ethernetSpeed = "";
        ethernetDuplex = "";
    }

    // ── Parsing ────────────────────────────────────────────────────────────

    function _ingest(text) {
        const lines = text.split("\n");
        let radioState = "";
        let dev = "";
        let type = "";
        let name = "";
        let uuid = "";
        let ip = "";
        let gw = "";
        let resolvers = [];
        let netSsid = "";
        let netSignal = 0;
        let netFreq = "";
        let netRate = "";
        let ethSpeed = "";
        let ethDuplex = "";
        let reachability = "";

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const space = line.indexOf(" ");
            if (space < 0)
                continue;
            const tag = line.slice(0, space);
            const value = line.slice(space + 1);

            if (tag === "RADIO") {
                radioState = value.trim();
            } else if (tag === "DEVICE") {
                dev = value.trim();
            } else if (tag === "CONNECTIVITY") {
                reachability = value.trim();
            } else if (tag === "INFO") {
                const parts = _split(value);
                const key = parts[0];
                const field = parts.slice(1).join(":");
                if (key === "GENERAL.TYPE")
                    type = field;
                else if (key === "GENERAL.CONNECTION")
                    name = field;
                else if (key === "GENERAL.CON-UUID")
                    uuid = field;
                else if (key === "IP4.GATEWAY")
                    gw = field;
                else if (key.indexOf("IP4.ADDRESS") === 0 && ip === "")
                    ip = field;
                else if (key.indexOf("IP4.DNS") === 0 && field !== "")
                    resolvers.push(field);
            } else if (tag === "WIFI") {
                const parts = _split(value);
                netSsid = parts[1] || "";
                netSignal = parseInt(parts[2] || "0", 10) || 0;
                netFreq = parts[3] || "";
                netRate = parts[4] || "";
            } else if (tag === "ETH") {
                const parts = value.split(" ");
                ethSpeed = parts[0] === "" || parts[0] === "-1" ? "" : parts[0];
                ethDuplex = parts[1] || "";
            }
        }

        if (busy !== "radio") {
            wifiRadio = radioState === "enabled";
            radioKnown = radioState !== "";
        }
        connectivity = reachability;

        if (dev === "" || (type !== "wifi" && type !== "ethernet")) {
            _clearLink();
            return;
        }

        device = dev;
        linkType = type;
        connectionName = name;
        connectionUuid = uuid;
        ipAddress = ip;
        gateway = gw;
        dns = resolvers.join(", ");
        ssid = type === "wifi" ? netSsid : "";
        signal = type === "wifi" ? netSignal : 0;
        frequency = netFreq;
        linkRate = netRate;
        ethernetSpeed = ethSpeed;
        ethernetDuplex = ethDuplex;

        for (let i = 0; i < networks.count; i++)
            networks.setProperty(i, "active", ssid !== "" && networks.get(i).ssid === ssid);
    }

    function _ingestScan(text) {
        const lines = text.split("\n");
        const seen = {};
        const found = [];

        for (let i = 0; i < lines.length; i++) {
            if (lines[i].trim() === "")
                continue;
            const parts = _split(lines[i]);
            const name = parts[1] || "";
            if (name === "")
                continue;

            const strength = parseInt(parts[2] || "0", 10) || 0;
            // The same network on two bands lists twice; keep the stronger.
            if (seen[name] !== undefined) {
                if (found[seen[name]].signal >= strength)
                    continue;
                found[seen[name]].signal = strength;
                continue;
            }

            seen[name] = found.length;
            found.push({
                ssid: name,
                signal: strength,
                security: parts[3] || "",
                frequency: parts[4] || "",
                active: parts[0] === "yes"
            });
        }

        found.sort((a, b) => b.signal - a.signal);

        networks.clear();
        for (let i = 0; i < found.length; i++)
            networks.append(found[i]);
    }

    Component.onCompleted: refresh()

    // ── Processes ──────────────────────────────────────────────────────────

    readonly property string _stateScript: 'dev=$(ip -o route show default 2>/dev/null | awk \'{for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }\'); ' + 'if [ -z "$dev" ]; then dev=$(nmcli -t -f TYPE,STATE,DEVICE dev status 2>/dev/null | awk -F: \'$2 ~ /^connected/ && ($1 == "wifi" || $1 == "ethernet") { print $3; exit }\'); fi; ' + 'echo "RADIO $(nmcli radio wifi 2>/dev/null)"; ' + 'echo "CONNECTIVITY $(nmcli networking connectivity check 2>/dev/null)"; ' + 'echo "DEVICE $dev"; ' + '[ -n "$dev" ] || exit 0; ' + 'nmcli -t -f GENERAL.TYPE,GENERAL.CONNECTION,GENERAL.CON-UUID,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS dev show "$dev" 2>/dev/null | sed "s/^/INFO /"; ' + 'kind=$(nmcli -t -f GENERAL.TYPE dev show "$dev" 2>/dev/null | cut -d: -f2); ' + 'if [ "$kind" = "wifi" ]; then nmcli -t -f ACTIVE,SSID,SIGNAL,FREQ,RATE dev wifi list ifname "$dev" 2>/dev/null | awk -F: \'/^yes/ { print "WIFI " $0; exit }\'; ' + 'elif [ "$kind" = "ethernet" ]; then echo "ETH $(cat /sys/class/net/$dev/speed 2>/dev/null) $(cat /sys/class/net/$dev/duplex 2>/dev/null)"; fi'

    readonly property string _enterpriseScript: 'iface=$(nmcli -t -f TYPE,DEVICE dev status | awk -F: \'$1 == "wifi" { print $2; exit }\'); ' + '[ -n "$4" ] && nmcli connection delete uuid "$4" >/dev/null 2>&1; ' + 'nmcli connection add type wifi ifname "$iface" con-name "$1" ssid "$1" ' + 'wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 ' + '802-1x.identity "$2" 802-1x.password "$3" && nmcli connection up id "$1"'

    readonly property Process _state: Process {
        id: state
        command: ["bash", "-c", root._stateScript]
        stdout: StdioCollector {
            onStreamFinished: root._ingest(this.text)
        }
    }

    readonly property Process _scanner: Process {
        id: scanner
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY,FREQ", "dev", "wifi", "list", "--rescan", "yes"]
        stdout: StdioCollector {
            onStreamFinished: root._ingestScan(this.text)
        }
    }

    readonly property Process _saved: Process {
        id: saved
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE", "con", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                known.clear();
                const lines = this.text.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    if (lines[i].trim() === "")
                        continue;
                    const parts = root._split(lines[i]);
                    known.append({ name: parts[0] || "", uuid: parts[1] || "", type: parts[2] || "" });
                }
            }
        }
    }

    readonly property Process _radio: Process {
        id: radio
        onExited: code => {
            root.busy = "";
            if (code !== 0)
                Toast.error("Could not change the Wi-Fi radio");
            root.refresh();
        }
    }

    readonly property Process _writer: Process {
        id: writer
        stderr: StdioCollector {
            id: writerErrors
        }
        onExited: code => {
            const was = root.busy;
            root.busy = "";

            if (code !== 0) {
                const reason = writerErrors.text.trim().split("\n").filter(line => line.trim() !== "").pop() || "Network request failed";
                root.error = reason;
                if (was === "")
                    root.connectFailed(reason);
                else
                    Toast.error(reason);
            } else if (was === "") {
                root.error = "";
                root.connectSucceeded();
            }

            root.refresh();
            if (was === "forget")
                root.loadKnown();
        }
    }

    readonly property Process _portal: Process {
        id: portal
        command: ["xdg-open", "http://networkcheck.kde.org"]
    }

    readonly property Timer _poll: Timer {
        interval: 8000
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
