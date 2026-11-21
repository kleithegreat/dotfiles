pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Networking

// Reactive state from Quickshell.Networking; on-demand nmcli for IP/DNS details and enterprise auth.
QtObject {
    id: root

    // ── State ──────────────────────────────────────────────────────────────

    readonly property bool wifiRadio: Networking.wifiEnabled
    readonly property bool radioKnown: Networking.backend === NetworkBackendType.NetworkManager
    readonly property bool wifiHardwareEnabled: Networking.wifiHardwareEnabled

    readonly property var _devices: Networking.devices.values
    readonly property var wifiDevice: _pickDevice(DeviceType.Wifi)
    readonly property var wiredDevice: _pickDevice(DeviceType.Wired)
    readonly property var _activeDevice: wiredDevice && wiredDevice.connected ? wiredDevice : wifiDevice && wifiDevice.connected ? wifiDevice : null

    // wifi · ethernet · ""
    readonly property string linkType: wiredDevice && wiredDevice.connected ? "ethernet" : wifiDevice && wifiDevice.connected ? "wifi" : ""
    readonly property string device: _activeDevice ? _activeDevice.name : ""

    readonly property var _rawWifiNetworks: wifiDevice ? wifiDevice.networks.values : []
    readonly property var _activeWifi: {
        for (let i = 0; i < _rawWifiNetworks.length; i++) {
            if (_rawWifiNetworks[i].connected)
                return _rawWifiNetworks[i];
        }
        return null;
    }

    readonly property string ssid: linkType === "wifi" && _activeWifi ? _activeWifi.name : ""
    readonly property int signal: linkType === "wifi" && _activeWifi ? _pct(_activeWifi.signalStrength) : 0
    readonly property string ethernetSpeed: linkType === "ethernet" && wiredDevice && wiredDevice.linkSpeed > 0 ? String(wiredDevice.linkSpeed) : ""

    property string connectionName: ""
    property string connectionUuid: ""
    property string ipAddress: ""
    property string gateway: ""
    property string dns: ""
    property string frequency: ""
    property string ethernetDuplex: ""

    property string busy: ""
    property bool _radioPending: false
    property WifiNetwork _activeConnectNet: null
    property string _enterpriseSecret: ""

    readonly property bool online: linkType !== ""
    readonly property bool captivePortal: Networking.connectivity === NetworkConnectivity.Portal || Networking.connectivity === NetworkConnectivity.Limited
    readonly property bool scanning: wifiDevice ? wifiDevice.scannerEnabled : false
    readonly property bool radioBusy: _radioPending

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
        if (!wifiRadio || linkType !== "wifi")
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

    signal connectSucceeded

    // ── Helpers ────────────────────────────────────────────────────────────

    function _pickDevice(kind) {
        let fallback = null;
        for (let i = 0; i < _devices.length; i++) {
            const dev = _devices[i];
            if (dev.type !== kind)
                continue;
            if (dev.connected)
                return dev;
            if (!fallback)
                fallback = dev;
        }
        return fallback;
    }

    function _pct(strength) {
        const value = Number(strength || 0);
        return value <= 1.0 ? Math.round(value * 100) : Math.round(value);
    }

    function _securityLabel(sec) {
        switch (sec) {
        case WifiSecurityType.Open:
        case WifiSecurityType.Owe:
        case WifiSecurityType.Unknown:
            return "";
        case WifiSecurityType.Wpa2Eap:
        case WifiSecurityType.WpaEap:
        case WifiSecurityType.Wpa3SuiteB192:
        case WifiSecurityType.DynamicWep:
        case WifiSecurityType.Leap:
            return "802.1X";
        case WifiSecurityType.Sae:
            return "WPA3";
        case WifiSecurityType.StaticWep:
            return "WEP";
        default:
            return "WPA2";
        }
    }

    function _findNetwork(name) {
        let best = null;
        for (let i = 0; i < _rawWifiNetworks.length; i++) {
            const net = _rawWifiNetworks[i];
            if (net.name !== name)
                continue;
            if (net.connected)
                return net;
            if (!best || _pct(net.signalStrength) > _pct(best.signalStrength))
                best = net;
        }
        return best;
    }

    // nmcli escapes field separators inside values (an SSID "a:b").
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

    function isKnown(name) {
        const net = _findNetwork(name);
        return net ? net.known : false;
    }

    function isEnterprise(security) {
        return String(security).indexOf("802.1X") >= 0;
    }

    function _syncNetworks() {
        const seen = {};
        const found = [];

        for (let i = 0; i < _rawWifiNetworks.length; i++) {
            const net = _rawWifiNetworks[i];
            const name = net.name || "";
            if (name === "")
                continue;

            const strength = _pct(net.signalStrength);
            if (seen[name] !== undefined) {
                const existing = found[seen[name]];
                if (net.connected)
                    existing.active = true;
                if (net.known)
                    existing.known = true;
                if (strength > existing.signal)
                    existing.signal = strength;
                continue;
            }

            seen[name] = found.length;
            found.push({
                ssid: name,
                signal: strength,
                security: _securityLabel(net.security),
                active: net.connected,
                known: net.known
            });
        }

        found.sort((a, b) => {
            if (a.active !== b.active)
                return a.active ? -1 : 1;
            if (a.known !== b.known)
                return a.known ? -1 : 1;
            return b.signal - a.signal;
        });

        networks.clear();
        for (let i = 0; i < found.length; i++)
            networks.append(found[i]);
    }

    on_RawWifiNetworksChanged: Qt.callLater(_syncNetworks)
    onSsidChanged: {
        Qt.callLater(_syncNetworks);
        Qt.callLater(refresh);
    }
    onDeviceChanged: Qt.callLater(refresh)
    onLinkTypeChanged: Qt.callLater(refresh)
    onScanningChanged: Qt.callLater(_syncNetworks)

    // ── Reads ──────────────────────────────────────────────────────────────

    function refresh() {
        if (device === "") {
            _clearDetails();
            return;
        }
        if (details.running)
            return;
        details.command = ["bash", "-c", _detailsScript, "--", device, linkType];
        details.running = true;
    }

    function scan() {
        if (wifiDevice)
            wifiDevice.scannerEnabled = true;
        refresh();
    }

    function stopScan() {
        if (wifiDevice)
            wifiDevice.scannerEnabled = false;
    }

    function _clearDetails() {
        connectionName = "";
        connectionUuid = "";
        ipAddress = "";
        gateway = "";
        dns = "";
        frequency = "";
        ethernetDuplex = "";
    }

    function _ingestDetails(text) {
        const lines = text.split("\n");
        let name = "";
        let uuid = "";
        let ip = "";
        let gw = "";
        const resolvers = [];
        let netFreq = "";
        let ethDuplex = "";

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const space = line.indexOf(" ");
            if (space < 0)
                continue;
            const tag = line.slice(0, space);
            const value = line.slice(space + 1);

            if (tag === "INFO") {
                const parts = _split(value);
                const key = parts[0];
                const field = parts.slice(1).join(":");
                if (key === "GENERAL.CONNECTION")
                    name = field;
                else if (key === "GENERAL.CON-UUID")
                    uuid = field;
                else if (key === "IP4.GATEWAY")
                    gw = field;
                else if (key.indexOf("IP4.ADDRESS") === 0 && ip === "")
                    ip = field;
                else if (key.indexOf("IP4.DNS") === 0 && field !== "")
                    resolvers.push(field);
            } else if (tag === "FREQ") {
                netFreq = value.trim();
            } else if (tag === "DUPLEX") {
                ethDuplex = value.trim();
            }
        }

        connectionName = name;
        connectionUuid = uuid;
        ipAddress = ip;
        gateway = gw;
        dns = resolvers.join(", ");
        frequency = netFreq;
        ethernetDuplex = ethDuplex;
    }

    // ── Writes ─────────────────────────────────────────────────────────────

    function setWifiRadio(enabled) {
        if (!radioKnown || _radioPending || wifiRadio === enabled)
            return;
        if (enabled && !wifiHardwareEnabled) {
            Toast.warning("Wi-Fi is disabled by hardware switch");
            return;
        }
        _radioPending = true;
        Networking.wifiEnabled = enabled;
        radioAbandon.restart();
    }

    function toggleWifiRadio() {
        setWifiRadio(!wifiRadio);
    }

    function _connectNative(net, psk) {
        _activeConnectNet = net;
        busy = "connect";
        if (psk !== undefined)
            net.connectWithPsk(psk);
        else
            net.connect();
    }

    // Returns what to ask the user for: "", "password" or "enterprise".
    function connect(name, security) {
        const net = _findNetwork(name);
        if (!net) {
            Toast.error("Network not found");
            return "";
        }
        // Saved profiles (including pre-configured NixOS eduroam) connect directly.
        if (net.known) {
            _connectNative(net);
            return "";
        }
        if (isEnterprise(security))
            return "enterprise";
        if (security !== "")
            return "password";

        _connectNative(net);
        return "";
    }

    function connectWithPassword(name, password) {
        const net = _findNetwork(name);
        if (!net) {
            Toast.error("Network not found");
            return;
        }
        _connectNative(net, password);
    }

    function connectEnterprise(name, identity, password) {
        if (busy !== "" || writer.running || enterprise.running)
            return;
        busy = "connect";
        _enterpriseSecret = String(password || "").replace(/[\r\n]/g, "");
        enterprise.command = ["bash", "-c", _enterpriseScript, "--", name, identity, device];
        enterprise.running = true;
    }

    function disconnect() {
        if (_activeWifi) {
            _activeWifi.disconnect();
            return;
        }
        if (wiredDevice && wiredDevice.connected) {
            wiredDevice.disconnect();
            return;
        }
        if (connectionUuid !== "" && busy === "" && !writer.running) {
            busy = "disconnect";
            writer.command = ["nmcli", "con", "down", "uuid", connectionUuid];
            writer.running = true;
        }
    }

    function forget(name) {
        const net = _findNetwork(name);
        if (!net || !net.known)
            return;
        net.forget();
        Qt.callLater(_syncNetworks);
    }

    // "auto" restores DHCP-provided servers.
    function setDns(server) {
        if (connectionUuid === "" || device === "" || busy !== "" || writer.running)
            return;
        busy = "dns";
        writer.command = ["bash", "-c", _dnsScript, "--", connectionUuid, server, device];
        writer.running = true;
    }

    Component.onCompleted: {
        _syncNetworks();
        refresh();
    }

    // ── Reactive & On-Demand Processes ────────────────────────────────────

    readonly property Connections _radioEvents: Connections {
        target: Networking
        function onWifiEnabledChanged() {
            root._radioPending = false;
            radioAbandon.stop();
        }
    }

    readonly property Timer _radioAbandon: Timer {
        id: radioAbandon
        interval: 2500
        onTriggered: root._radioPending = false
    }

    readonly property Connections _connectEvents: Connections {
        target: root._activeConnectNet
        function onConnectedChanged() {
            if (root._activeConnectNet && root._activeConnectNet.connected) {
                root.busy = "";
                root._activeConnectNet = null;
                root.connectSucceeded();
                root.refresh();
            }
        }
        function onConnectionFailed(reason) {
            root.busy = "";
            root._activeConnectNet = null;
            Toast.error(ConnectionFailReason.toString(reason) || "Connection failed");
        }
    }

    readonly property string _detailsScript: 'dev="$1"; kind="$2"; ' + 'nmcli --terse --fields GENERAL.CONNECTION,GENERAL.CON-UUID,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS dev show "$dev" 2>/dev/null | sed "s/^/INFO /"; ' + 'if [ "$kind" = "wifi" ]; then freq=$(nmcli --terse --fields ACTIVE,FREQ dev wifi list ifname "$dev" 2>/dev/null | awk --field-separator=: \'/^yes/{print $2; exit}\'); [ -n "$freq" ] && echo "FREQ $freq"; ' + 'elif [ "$kind" = "ethernet" ]; then duplex=$(cat "/sys/class/net/$dev/duplex" 2>/dev/null); [ -n "$duplex" ] && echo "DUPLEX $duplex"; fi'

    readonly property string _dnsScript: 'if [ "$2" = "auto" ]; then nmcli con mod uuid "$1" ipv4.dns "" ipv4.ignore-auto-dns no; ' + 'else nmcli con mod uuid "$1" ipv4.dns "$2" ipv4.ignore-auto-dns yes; fi && nmcli dev reapply "$3"'

    readonly property string _enterpriseScript: 'iface="$3"; ' + 'if [ -z "$iface" ]; then iface=$(nmcli --terse --fields TYPE,DEVICE dev status | awk --field-separator=: \'$1 == "wifi" { print $2; exit }\'); fi; ' + 'pwfile=$(mktemp); chmod 600 "$pwfile"; trap \'rm --force "$pwfile"\' EXIT; ' + 'IFS= read -r pw; printf \'802-1x.password:%s\n\' "$pw" > "$pwfile"; ' + 'nmcli connection add type wifi ifname "$iface" con-name "$1" ssid "$1" ' + 'wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 802-1x.identity "$2" && ' + 'nmcli connection up id "$1" passwd-file "$pwfile"'

    readonly property Process _details: Process {
        id: details
        stdout: StdioCollector {
            onStreamFinished: root._ingestDetails(this.text)
        }
    }

    readonly property Process _enterprise: Process {
        id: enterprise
        stdinEnabled: true
        stderr: StdioCollector {
            id: enterpriseErrors
        }
        onStarted: {
            enterprise.write(root._enterpriseSecret + "\n");
            root._enterpriseSecret = "";
        }
        onExited: code => {
            root._enterpriseSecret = "";
            root.busy = "";
            if (code !== 0)
                Toast.failure(enterpriseErrors.text, "Enterprise connection failed");
            else
                root.connectSucceeded();
            root.refresh();
        }
    }

    readonly property Process _writer: Process {
        id: writer
        stderr: StdioCollector {
            id: writerErrors
        }
        onExited: code => {
            root.busy = "";
            if (code !== 0)
                Toast.failure(writerErrors.text, "Network request failed");
            root.refresh();
        }
    }
}
