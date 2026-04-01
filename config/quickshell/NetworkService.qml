pragma Singleton
import QtQuick
import Quickshell.Io
import "." as Root

QtObject {
    id: root

    // ── Connection state ──
    readonly property bool wifiEnabled: _wifiEnabled
    readonly property bool wifiRadioReady: _wifiRadioReady
    readonly property bool wifiRadioBusy: wifiRadioCheckProc.running || wifiRadioToggleProc.running
    readonly property string connectedSsid: _connectedSsid
    readonly property string connectedConnectionId: _connectedConnectionId
    readonly property string connectedConnectionUuid: _connectedConnectionUuid
    readonly property string connectivityState: _connectivityState
    readonly property string primaryConnectionType: _primaryConnectionType
    readonly property string primaryConnectionLabel: _primaryConnectionLabel
    readonly property bool isCaptivePortal: _connectivityState === "portal" || _connectivityState === "limited"
    readonly property string connectError: _connectError

    // ── Network models ──
    readonly property var networksModel: netModel
    readonly property var knownNetworksModel: knownModel

    // ── Target network state ──
    readonly property string targetSsid: _targetSsid
    readonly property string targetSecurity: _targetSecurity
    readonly property int targetSignal: _targetSignal
    readonly property bool targetIsConnected: _targetIsConnected
    readonly property bool targetIsKnown: _targetIsKnown
    readonly property string targetConnectionId: _targetConnectionId
    readonly property string targetConnectionUuid: _targetConnectionUuid

    // ── Detail state ──
    readonly property string detailIp: _detailIp
    readonly property string detailGateway: _detailGateway
    readonly property string detailDns: _detailDns
    readonly property string detailFreq: _detailFreq

    // ── Diagnostics state ──
    readonly property bool diagLoading: _diagLoading
    readonly property bool speedTestRunning: _speedTestRunning
    readonly property string diagBand: _diagBand
    readonly property string diagSignal: _diagSignal
    readonly property string diagNoise: _diagNoise
    readonly property string diagLinkRate: _diagLinkRate
    readonly property string diagGateway: _diagGateway
    readonly property string diagGwPing: _diagGwPing
    readonly property string diagGwJitter: _diagGwJitter
    readonly property string diagGwLoss: _diagGwLoss
    readonly property string diagNetPing: _diagNetPing
    readonly property string diagNetJitter: _diagNetJitter
    readonly property string diagNetLoss: _diagNetLoss
    readonly property string diagDnsServer: _diagDnsServer
    readonly property string diagDnsTime: _diagDnsTime
    readonly property string diagDownload: _diagDownload
    readonly property string diagUpload: _diagUpload
    readonly property string diagBufferbloat: _diagBufferbloat
    readonly property bool diagBufferbloatOk: _diagBufferbloatOk
    readonly property string diagWifiStandard: _diagWifiStandard
    readonly property bool exportCopied: _exportCopied

    // ── Sparkline history (last 30 samples) ──
    readonly property var histSignal: _histSignal
    readonly property var histNoise: _histNoise
    readonly property var histGwPing: _histGwPing
    readonly property var histGwJitter: _histGwJitter
    readonly property var histGwLoss: _histGwLoss
    readonly property var histNetPing: _histNetPing
    readonly property var histNetJitter: _histNetJitter
    readonly property var histNetLoss: _histNetLoss
    readonly property var histDnsTime: _histDnsTime

    // ── Channel scanner state ──
    readonly property string currentChannel: _currentChannel
    readonly property string currentBand: _currentBand
    readonly property var channelEntriesModel: channelModel
    readonly property bool scanning: scanProc.running
    readonly property bool channelScanning: channelScanProc.running

    // ── Signals for async results ──
    signal connectSucceeded()
    signal connectFailed()
    signal disconnected()
    signal networkForgotten()

    // ── Internal staging ──────────────────────────────────────

    property bool _wifiEnabled: false
    property bool _wifiRadioReady: false
    property string _connectedSsid: ""
    property string _connectedConnectionId: ""
    property string _connectedConnectionUuid: ""
    property string _connectivityState: ""
    property string _primaryConnectionType: ""
    property string _primaryConnectionLabel: ""
    property string _connectError: ""

    property string _targetSsid: ""
    property string _targetSecurity: ""
    property int _targetSignal: 0
    property bool _targetIsConnected: false
    property bool _targetIsKnown: false
    property string _targetConnectionId: ""
    property string _targetConnectionUuid: ""

    property string _detailIp: ""
    property string _detailGateway: ""
    property string _detailDns: ""
    property string _detailFreq: ""

    property bool _diagLoading: false
    property bool _speedTestRunning: false
    property string _diagBand: ""
    property string _diagSignal: ""
    property string _diagNoise: ""
    property string _diagLinkRate: ""
    property string _diagGateway: ""
    property string _diagGwPing: ""
    property string _diagGwJitter: ""
    property string _diagGwLoss: ""
    property string _diagNetPing: ""
    property string _diagNetJitter: ""
    property string _diagNetLoss: ""
    property string _diagDnsServer: ""
    property string _diagDnsTime: ""
    property string _diagDownload: ""
    property string _diagUpload: ""
    property string _diagBufferbloat: ""
    property bool _diagBufferbloatOk: true
    property string _bloatBase: ""
    property string _bloatLoad: ""
    property string _diagWifiStandard: ""
    property bool _exportCopied: false

    property var _histSignal: []
    property var _histNoise: []
    property var _histGwPing: []
    property var _histGwJitter: []
    property var _histGwLoss: []
    property var _histNetPing: []
    property var _histNetJitter: []
    property var _histNetLoss: []
    property var _histDnsTime: []

    property string _currentChannel: ""
    property string _currentBand: ""
    property bool _diagPolling: false
    property var _chanMap: ({})
    property bool _scanAfterRadioRefresh: false
    property bool _wifiTargetEnabled: false

    // ── Models ──
    property ListModel netModel: ListModel {}
    property ListModel knownModel: ListModel {}
    property ListModel channelModel: ListModel {}

    Component.onCompleted: refreshSummary()

    // ── Public API ────────────────────────────────────────────

    function refreshSummary() {
        refreshRadio();
        refreshConnection();
    }

    function scan() {
        clearLiveWifiState();
        _scanAfterRadioRefresh = true;
        refreshRadio();
    }

    function refreshRadio() {
        if (!wifiRadioCheckProc.running)
            wifiRadioCheckProc.running = true;
    }

    function refreshConnection() {
        if (!activeProc.running)
            activeProc.running = true;
        if (!connectivityProc.running)
            connectivityProc.running = true;
    }

    function setWifiEnabled(enabled) {
        if (wifiRadioBusy)
            return;
        if (_wifiRadioReady && _wifiEnabled === enabled)
            return;
        _wifiTargetEnabled = enabled;
        wifiRadioToggleProc.command = ["nmcli", "radio", "wifi", enabled ? "on" : "off"];
        wifiRadioToggleProc.running = true;
    }

    function toggleWifiRadio() {
        setWifiEnabled(!_wifiEnabled);
    }

    function loadKnown() {
        knownModel.clear();
        knownProc.running = true;
    }

    // Returns the popup state the caller should transition to:
    // "enterprise" | "connecting" | "password"
    function connectTo(ssid, security) {
        _connectError = "";

        if (isEnterprise(security)) {
            _targetSsid = ssid;
            _targetSecurity = security;
            _targetConnectionId = connectionIdForSsid(ssid);
            _targetConnectionUuid = connectionUuidForSsid(ssid);
            return "enterprise";
        } else if (isKnown(ssid)) {
            let uuid = connectionUuidForSsid(ssid);
            let id = connectionIdForSsid(ssid);
            _targetSsid = ssid;
            if (uuid !== "")
                connectProc.command = ["nmcli", "con", "up", "uuid", uuid];
            else
                connectProc.command = ["nmcli", "con", "up", "id", id];
            connectProc.running = true;
            return "connecting";
        } else if (security !== "") {
            _targetSsid = ssid;
            _targetSecurity = security;
            return "password";
        } else {
            _targetSsid = ssid;
            connectProc.command = ["nmcli", "dev", "wifi", "connect", ssid];
            connectProc.running = true;
            return "connecting";
        }
    }

    function submitPassword(password) {
        connectProc.command = ["nmcli", "dev", "wifi", "connect", _targetSsid, "password", password];
        connectProc.running = true;
    }

    function submitEnterprise(identity, password) {
        enterpriseProc.command = [
            "bash", "-c",
            'iface=$(nmcli -t -f DEVICE,TYPE dev | grep ":wifi$" | head -1 | cut -d: -f1); ' +
            'if [ -n "$4" ]; then nmcli connection delete uuid "$4" 2>/dev/null; ' +
            'elif [ -n "$5" ]; then nmcli connection delete id "$5" 2>/dev/null; fi; ' +
            'nmcli connection add type wifi ifname "$iface" con-name "$1" ssid "$1" ' +
            'wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 ' +
            '802-1x.identity "$2" 802-1x.password "$3" && ' +
            'nmcli connection up id "$1"',
            "--", _targetSsid, identity, password, _targetConnectionUuid, _targetConnectionId
        ];
        enterpriseProc.running = true;
    }

    function disconnect() {
        if (_connectedConnectionUuid === "") return;
        disconnectProc.command = ["nmcli", "con", "down", "uuid", _connectedConnectionUuid];
        disconnectProc.running = true;
    }

    function forgetNetwork() {
        let uuid = _targetConnectionUuid;
        let id = _targetConnectionId;
        if (uuid !== "")
            forgetProc.command = ["nmcli", "con", "delete", "uuid", uuid];
        else if (id !== "")
            forgetProc.command = ["nmcli", "con", "delete", "id", id];
        else
            return;
        forgetProc.running = true;
    }

    function openDetail(ssid, security, signal, isActive) {
        _targetSsid = ssid;
        _targetSecurity = security;
        _targetSignal = signal;
        _targetConnectionId = connectionIdForSsid(ssid);
        _targetConnectionUuid = connectionUuidForSsid(ssid);
        _targetIsConnected = isActive;
        _targetIsKnown = _targetConnectionId !== "" || _targetConnectionUuid !== "";
        _detailIp = ""; _detailGateway = ""; _detailDns = ""; _detailFreq = "";
        _connectError = "";
        if (isActive) {
            detailProc.command = [
                "bash", "-c",
                'ref_kind=id; ref="$1"; ' +
                'if [ -n "$2" ]; then ref_kind=uuid; ref="$2"; elif [ -n "$3" ]; then ref="$3"; fi; ' +
                'echo "IP|$(nmcli -t -f IP4.ADDRESS con show "$ref_kind" "$ref" 2>/dev/null | head -1 | cut -d: -f2)"; ' +
                'echo "GW|$(nmcli -t -f IP4.GATEWAY con show "$ref_kind" "$ref" 2>/dev/null | head -1 | cut -d: -f2)"; ' +
                'echo "DNS|$(nmcli -t -f IP4.DNS con show "$ref_kind" "$ref" 2>/dev/null | head -1 | cut -d: -f2)"; ' +
                'freq=$(nmcli -t -f IN-USE,FREQ dev wifi list 2>/dev/null | grep "^\\*" | head -1 | cut -d: -f2); ' +
                'freq=$(echo "$freq" | tr -dc "0-9"); ' +
                'if [ -n "$freq" ]; then ' +
                '  if [ "$freq" -lt 3000 ] 2>/dev/null; then freq="$freq MHz (2.4 GHz)"; ' +
                '  elif [ "$freq" -lt 6000 ] 2>/dev/null; then freq="$freq MHz (5 GHz)"; ' +
                '  else freq="$freq MHz (6 GHz)"; fi; ' +
                'fi; ' +
                'echo "FREQ|${freq:-}"',
                "--", ssid, _targetConnectionUuid, _targetConnectionId
            ];
            detailProc.running = true;
        }
    }

    function startDiagnostics() {
        _diagBand = ""; _diagSignal = ""; _diagNoise = ""; _diagLinkRate = "";
        _diagGateway = ""; _diagGwPing = ""; _diagGwJitter = ""; _diagGwLoss = "";
        _diagNetPing = ""; _diagNetJitter = ""; _diagNetLoss = "";
        _diagDnsServer = ""; _diagDnsTime = "";
        _diagDownload = ""; _diagUpload = "";
        _diagBufferbloat = ""; _diagBufferbloatOk = true; _bloatBase = ""; _bloatLoad = "";
        _diagWifiStandard = "";
        _histSignal = []; _histNoise = [];
        _histGwPing = []; _histGwJitter = []; _histGwLoss = [];
        _histNetPing = []; _histNetJitter = []; _histNetLoss = [];
        _histDnsTime = [];
        _diagLoading = true; _speedTestRunning = false;
        _diagPolling = true;
        wifiInfoProc.running = true;
        gwPingProc.running = true;
        netPingProc.running = true;
        dnsProc.running = true;
    }

    function startSpeedTest() {
        _diagDownload = ""; _diagUpload = ""; _diagBufferbloat = "";
        _speedTestRunning = true;
        speedTestProc.running = true;
    }

    function startChannelScan() {
        channelModel.clear();
        _currentChannel = ""; _currentBand = "";
        channelScanProc.running = true;
    }

    function switchDns(server) {
        if (_connectedConnectionUuid === "") return;
        if (server === "auto") {
            dnsSwitchProc.command = ["nmcli", "con", "mod", "uuid", _connectedConnectionUuid, "ipv4.dns", "", "ipv4.ignore-auto-dns", "no"];
        } else {
            dnsSwitchProc.command = ["nmcli", "con", "mod", "uuid", _connectedConnectionUuid, "ipv4.dns", server, "ipv4.ignore-auto-dns", "yes"];
        }
        dnsSwitchProc.running = true;
    }

    function openCaptivePortal() {
        captiveOpenProc.running = true;
    }

    function exportReport() {
        let colorLabel = function(val, goodThresh, warnThresh, isLower) {
            let v = parseFloat(val);
            if (isNaN(v)) return "\u26AA";
            if (isLower) return v <= goodThresh ? "\uD83D\uDFE2" : (v <= warnThresh ? "\uD83D\uDFE1" : "\uD83D\uDD34");
            return v >= goodThresh ? "\uD83D\uDFE2" : (v >= warnThresh ? "\uD83D\uDFE1" : "\uD83D\uDD34");
        };

        let report = "WHYFI DIAGNOSTIC REPORT\n";
        report += "Generated: " + Qt.formatDateTime(new Date(), "yyyy-MM-dd hh:mm:ss") + "\n\n";
        report += "Legend: \uD83D\uDFE2 Good  \uD83D\uDFE1 Warning  \uD83D\uDD34 Poor\n\n";

        report += "NETWORK\n";
        report += "  SSID: " + _connectedSsid + "\n";
        report += "  Band: " + (_diagBand || "--") + "\n";
        report += "  Standard: " + (_diagWifiStandard || "--") + "\n";
        report += "  Channel: " + (_currentChannel || "--") + "\n\n";

        report += "SIGNAL\n";
        report += "  " + colorLabel(_diagSignal, -50, -70, false) + " Signal: " + (_diagSignal !== "" && _diagSignal !== "--" ? _diagSignal + " dBm" : "--") + "\n";
        report += "  Noise: " + (_diagNoise !== "" && _diagNoise !== "--" ? _diagNoise + " dBm" : "--") + "\n";
        report += "  Link Rate: " + (_diagLinkRate !== "" && _diagLinkRate !== "--" ? _diagLinkRate + " Mbps" : "--") + "\n\n";

        report += "ROUTER \u00B7 " + (_diagGateway || "--") + "\n";
        report += "  " + colorLabel(_diagGwPing, 10, 50, true) + " Ping: " + (_diagGwPing !== "" && _diagGwPing !== "--" ? _diagGwPing + " ms" : "--") + "\n";
        report += "  " + colorLabel(_diagGwJitter, 5, 20, true) + " Jitter: " + (_diagGwJitter !== "" && _diagGwJitter !== "--" ? _diagGwJitter + " ms" : "--") + "\n";
        report += "  " + colorLabel(_diagGwLoss, 0, 2, true) + " Loss: " + (_diagGwLoss !== "" && _diagGwLoss !== "--" ? _diagGwLoss + "%" : "--") + "\n\n";

        report += "INTERNET \u00B7 1.1.1.1\n";
        report += "  " + colorLabel(_diagNetPing, 20, 50, true) + " Ping: " + (_diagNetPing !== "" && _diagNetPing !== "--" ? _diagNetPing + " ms" : "--") + "\n";
        report += "  " + colorLabel(_diagNetJitter, 10, 30, true) + " Jitter: " + (_diagNetJitter !== "" && _diagNetJitter !== "--" ? _diagNetJitter + " ms" : "--") + "\n";
        report += "  " + colorLabel(_diagNetLoss, 0, 2, true) + " Loss: " + (_diagNetLoss !== "" && _diagNetLoss !== "--" ? _diagNetLoss + "%" : "--") + "\n\n";

        report += "DNS \u00B7 " + (_diagDnsServer || "--") + "\n";
        report += "  " + colorLabel(_diagDnsTime, 30, 100, true) + " Lookup: " + (_diagDnsTime !== "" && _diagDnsTime !== "--" ? _diagDnsTime + " ms" : "--") + "\n\n";

        if (_diagDownload !== "") {
            report += "SPEED TEST\n";
            report += "  Download: " + _diagDownload + " Mbps\n";
            report += "  Upload: " + _diagUpload + " Mbps\n";
            if (_diagBufferbloat !== "") {
                report += "  " + (_diagBufferbloatOk ? "\uD83D\uDFE2" : "\uD83D\uDD34") + " " + _diagBufferbloat + "\n";
            }
            report += "\n";
        }

        report += "Paste this into ChatGPT or Claude for help diagnosing issues.";

        exportProc.command = ["bash", "-c", "printf '%s' \"$1\" | wl-copy", "--", report];
        exportProc.running = true;
    }

    function resetTarget() {
        _targetSsid = ""; _targetSecurity = ""; _targetSignal = 0;
        _targetIsConnected = false; _targetIsKnown = false;
        _connectError = "";
        _targetConnectionId = ""; _targetConnectionUuid = "";
        _detailIp = ""; _detailGateway = ""; _detailDns = ""; _detailFreq = "";
        _diagLoading = false; _speedTestRunning = false;
        _diagPolling = false;
    }

    function clearLiveWifiState() {
        netModel.clear();
        _connectedSsid = "";
        _connectedConnectionId = "";
        _connectedConnectionUuid = "";
        _connectivityState = "";
    }

    // ── Utility functions ─────────────────────────────────────

    function parseNmcli(line) {
        let fields = [], cur = "";
        for (let i = 0; i < line.length; i++) {
            if (line[i] === '\\' && i + 1 < line.length) { cur += line[i + 1]; i++; }
            else if (line[i] === ':') { fields.push(cur); cur = ""; }
            else cur += line[i];
        }
        fields.push(cur);
        return fields;
    }

    function isEnterprise(sec) { return sec.indexOf("802.1X") >= 0; }

    function signalIcon(sig) {
        if (sig > 75) return "󰤨";
        if (sig > 50) return "󰤥";
        if (sig > 25) return "󰤢";
        return "󰤟";
    }

    function knownConnection(ssid) {
        for (let i = 0; i < knownModel.count; i++) {
            let entry = knownModel.get(i);
            if (entry.ssid === ssid) return entry;
        }
        return null;
    }

    function isKnown(ssid) {
        return knownConnection(ssid) !== null;
    }

    function connectionIdForSsid(ssid) {
        if (_connectedSsid === ssid && _connectedConnectionId !== "")
            return _connectedConnectionId;
        let entry = knownConnection(ssid);
        return entry ? (entry.id || "") : "";
    }

    function connectionUuidForSsid(ssid) {
        if (_connectedSsid === ssid && _connectedConnectionUuid !== "")
            return _connectedConnectionUuid;
        let entry = knownConnection(ssid);
        return entry ? (entry.uuid || "") : "";
    }

    function signalColor(dbm) {
        let v = parseInt(dbm);
        if (isNaN(v)) return Root.Theme.fg4;
        if (v >= -50) return Root.Theme.greenBright;
        if (v >= -70) return Root.Theme.yellowBright;
        return Root.Theme.redBright;
    }

    function pingColor(ms) {
        let v = parseFloat(ms);
        if (isNaN(v)) return Root.Theme.fg4;
        if (v < 20) return Root.Theme.greenBright;
        if (v < 50) return Root.Theme.yellowBright;
        return Root.Theme.redBright;
    }

    function lossColor(pct) {
        let v = parseFloat(pct);
        if (isNaN(v)) return Root.Theme.fg4;
        if (v === 0) return Root.Theme.greenBright;
        if (v <= 2) return Root.Theme.yellowBright;
        return Root.Theme.redBright;
    }

    function qualityScore() {
        let score = 100;
        let hasData = false;

        let sig = parseInt(_diagSignal);
        if (!isNaN(sig)) {
            hasData = true;
            let sigScore = Math.max(0, Math.min(100, ((sig + 90) / 60) * 100));
            score = Math.min(score, sigScore);
        }

        let gwP = parseFloat(_diagGwPing);
        if (!isNaN(gwP)) {
            hasData = true;
            let pingScore = Math.max(0, Math.min(100, 100 - gwP));
            score = Math.min(score, pingScore);
        }

        let netP = parseFloat(_diagNetPing);
        if (!isNaN(netP)) {
            hasData = true;
            let netScore = Math.max(0, Math.min(100, 100 - (netP / 2)));
            score = Math.min(score, netScore);
        }

        let gwL = parseFloat(_diagGwLoss);
        if (!isNaN(gwL) && gwL > 0) {
            hasData = true;
            score = Math.min(score, Math.max(0, 100 - gwL * 20));
        }
        let netL = parseFloat(_diagNetLoss);
        if (!isNaN(netL) && netL > 0) {
            hasData = true;
            score = Math.min(score, Math.max(0, 100 - netL * 15));
        }

        return hasData ? Math.round(score) : -1;
    }

    function qualityLabel(score) {
        if (score < 0) return "";
        if (score >= 80) return "Excellent";
        if (score >= 60) return "Good";
        if (score >= 40) return "Fair";
        if (score >= 20) return "Poor";
        return "Very Poor";
    }

    function qualityColor(score) {
        if (score < 0) return Root.Theme.fg4;
        if (score >= 80) return Root.Theme.greenBright;
        if (score >= 60) return Root.Theme.aquaBright;
        if (score >= 40) return Root.Theme.yellowBright;
        return Root.Theme.redBright;
    }

    // ── Radio processes ───────────────────────────────────────

    property Process wifiRadioCheckProc: Process {
        running: false
        command: ["nmcli", "radio", "wifi"]
        stdout: SplitParser { onRead: (line) => {
            let state = line.trim();
            if (state === "")
                return;
            root._wifiEnabled = state === "enabled";
            root._wifiRadioReady = true;
            if (!root._wifiEnabled)
                root.clearLiveWifiState();
        } }
        onExited: (code, status) => {
            if (root._scanAfterRadioRefresh) {
                root._scanAfterRadioRefresh = false;
                if (root._wifiEnabled) {
                    root.scanProc.running = true;
                    root.connectivityProc.running = true;
                } else {
                    root._connectivityState = "";
                }
            }
            if (code !== 0)
                console.log("[wifi-radio-check] exit", code);
        }
    }

    property Process wifiRadioToggleProc: Process {
        running: false
        onExited: (code, status) => {
            if (code === 0) {
                if (root._wifiTargetEnabled) {
                    root.scan();
                    root.loadKnown();
                } else {
                    root.refreshSummary();
                }
            } else {
                console.log("[wifi-radio-toggle] exit", code);
                root.refreshSummary();
            }
        }
    }

    // ── Scan processes ────────────────────────────────────────

    property Process scanProc: Process {
        command: [
            "bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1); " +
            "nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE dev wifi list ifname \"$iface\" --rescan yes"
        ]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let p = root.parseNmcli(line);
            if (p.length < 4 || !p[0]) return;
            let isActive = p[3] === "*";
            let sig = parseInt(p[1]) || 0;
            if (isActive) root._connectedSsid = p[0];
            for (let i = 0; i < root.netModel.count; i++) {
                if (root.netModel.get(i).ssid === p[0]) {
                    if (isActive || sig > root.netModel.get(i).signal)
                        root.netModel.set(i, { ssid: p[0], signal: Math.max(sig, root.netModel.get(i).signal), security: p[2] || "", active: isActive || root.netModel.get(i).active });
                    return;
                }
            }
            root.netModel.append({ ssid: p[0], signal: sig, security: p[2] || "", active: isActive });
        } }
        onExited: (code, status) => { root.activeProc.running = true; }
    }

    property Process knownProc: Process {
        command: [
            "bash", "-c",
            "escape() { local value=\"$1\"; value=${value//\\\\/\\\\\\\\}; value=${value//:/\\\\:}; printf '%s' \"$value\"; }; " +
            "nmcli -t -f UUID,TYPE con show | while IFS=: read -r uuid type; do " +
            "  [ \"$type\" = '802-11-wireless' ] || continue; " +
            "  id=$(nmcli -g connection.id con show uuid \"$uuid\" 2>/dev/null | head -1); " +
            "  ssid=$(nmcli -g 802-11-wireless.ssid con show uuid \"$uuid\" 2>/dev/null | head -1); " +
            "  [ -n \"$id\" ] || continue; " +
            "  [ -n \"$ssid\" ] || ssid=\"$id\"; " +
            "  printf '%s:%s:%s\\n' \"$(escape \"$id\")\" \"$(escape \"$uuid\")\" \"$(escape \"$ssid\")\"; " +
            "done"
        ]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let parts = root.parseNmcli(line);
            if (parts.length < 3) return;
            root.knownModel.append({
                id: parts[0],
                uuid: parts[1],
                ssid: parts[2] || parts[0]
            });
        } }
    }

    property Process activeProc: Process {
        id: activeProc
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE", "con", "show", "--active"]
        running: false
        property string pendingWifiSsid: ""
        property string pendingWifiId: ""
        property string pendingWifiUuid: ""
        property bool sawWifi: false
        property string pendingPrimaryType: ""
        property string pendingPrimaryLabel: ""
        onRunningChanged: {
            if (running) {
                pendingWifiSsid = "";
                pendingWifiId = "";
                pendingWifiUuid = "";
                sawWifi = false;
                pendingPrimaryType = "";
                pendingPrimaryLabel = "";
            }
        }
        stdout: SplitParser { onRead: (line) => {
            let parts = root.parseNmcli(line);
            if (parts.length < 4)
                return;

            if (parts[2] === "802-3-ethernet") {
                activeProc.pendingPrimaryType = "ethernet";
                activeProc.pendingPrimaryLabel = "Ethernet";
                return;
            }

            if (parts[2] !== "802-11-wireless")
                return;

            let ssid = parts[0] || "";
            activeProc.sawWifi = true;
            activeProc.pendingWifiSsid = ssid;
            activeProc.pendingWifiId = parts[0] || "";
            activeProc.pendingWifiUuid = parts[1] || "";
            if (activeProc.pendingPrimaryType !== "ethernet") {
                activeProc.pendingPrimaryType = "wifi";
                activeProc.pendingPrimaryLabel = ssid;
            }
            for (let i = 0; i < root.netModel.count; i++) {
                if (root.netModel.get(i).ssid === ssid) {
                    root.netModel.setProperty(i, "active", true);
                    return;
                }
            }
        } }
        onExited: {
            root._connectedSsid = activeProc.sawWifi ? activeProc.pendingWifiSsid : "";
            root._connectedConnectionId = activeProc.sawWifi ? activeProc.pendingWifiId : "";
            root._connectedConnectionUuid = activeProc.sawWifi ? activeProc.pendingWifiUuid : "";
            root._primaryConnectionType = activeProc.pendingPrimaryType;
            root._primaryConnectionLabel = activeProc.pendingPrimaryLabel;
        }
    }

    // ── Connection processes ──────────────────────────────────

    property Process connectProc: Process {
        running: false
        onExited: (code, status) => {
            if (code === 0) {
                root.resetTarget();
                root.scan();
                root.loadKnown();
                root.connectSucceeded();
            } else {
                root._connectError = "Connection failed (exit " + code + ")";
                root.connectFailed();
            }
        }
    }

    property Process enterpriseProc: Process {
        running: false
        onExited: (code, status) => {
            if (code === 0) {
                root.resetTarget();
                root.scan();
                root.loadKnown();
                root.connectSucceeded();
            } else {
                root._connectError = "Enterprise auth failed (exit " + code + ")";
                root.connectFailed();
            }
        }
    }

    property Process disconnectProc: Process {
        running: false
        onExited: (code, status) => {
            root._connectedSsid = "";
            root._connectedConnectionId = "";
            root._connectedConnectionUuid = "";
            root.resetTarget();
            root.scan();
            root.disconnected();
        }
    }

    property Process forgetProc: Process {
        running: false
        onExited: (code, status) => {
            root.resetTarget();
            root.scan();
            root.loadKnown();
            root.networkForgotten();
        }
    }

    property Process detailProc: Process {
        running: false
        stdout: SplitParser { onRead: (line) => {
            if (line.startsWith("IP|"))   root._detailIp      = line.substring(3).trim();
            if (line.startsWith("GW|"))   root._detailGateway  = line.substring(3).trim();
            if (line.startsWith("DNS|"))  root._detailDns      = line.substring(4).trim();
            if (line.startsWith("FREQ|")) root._detailFreq     = line.substring(5).trim();
        } }
    }

    // ── Diagnostics processes ─────────────────────────────────

    property Process wifiInfoProc: Process {
        running: false
        command: ["bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi' | head -1 | cut -d: -f1); " +
            "[ -z \"$iface\" ] && exit 1; " +
            "link=$(iw dev \"$iface\" link 2>/dev/null); " +
            "signal=$(echo \"$link\" | awk '/signal:/{print $2}'); " +
            "rate=$(echo \"$link\" | awk '/tx bitrate:/{print $3}'); " +
            "freq=$(echo \"$link\" | awk '/freq:/{print $2}'); " +
            "if [ -z \"$signal\" ]; then " +
            "  pct=$(nmcli -t -f IN-USE,SIGNAL dev wifi list ifname \"$iface\" 2>/dev/null | grep '^\\*' | head -1 | cut -d: -f2); " +
            "  [ -n \"$pct\" ] && signal=$(( (pct / 2) - 100 )); " +
            "fi; " +
            "if [ -z \"$freq\" ]; then " +
            "  freq=$(nmcli -t -f IN-USE,FREQ dev wifi list ifname \"$iface\" 2>/dev/null | grep '^\\*' | head -1 | cut -d: -f2); " +
            "  [ -n \"$freq\" ] && freq=$(echo \"$freq\" | tr -dc \"0-9\"); " +
            "fi; " +
            "if [ -z \"$rate\" ]; then " +
            "  rate=$(nmcli -f WIFI.BITRATE dev show \"$iface\" 2>/dev/null | awk '{gsub(/[^0-9.]/, \"\"); print}' | head -1); " +
            "fi; " +
            "noise=$(iw dev \"$iface\" survey dump 2>/dev/null | awk '/\\[in use\\]/{f=1} f && /noise/{print $2; exit}'); " +
            "band=''; " +
            "if [ -n \"$freq\" ]; then " +
            "  if [ \"$freq\" -lt 3000 ] 2>/dev/null; then band='2.4 GHz'; " +
            "  elif [ \"$freq\" -lt 6000 ] 2>/dev/null; then band='5 GHz'; " +
            "  else band='6 GHz'; fi; " +
            "fi; " +
            "wifi_std=''; " +
            "if echo \"$link\" | grep -q 'EHT'; then wifi_std='Wi-Fi 7 (802.11be)'; " +
            "elif echo \"$link\" | grep -q 'HE'; then wifi_std='Wi-Fi 6 (802.11ax)'; " +
            "elif echo \"$link\" | grep -q 'VHT'; then wifi_std='Wi-Fi 5 (802.11ac)'; " +
            "elif echo \"$link\" | grep -q 'HT'; then wifi_std='Wi-Fi 4 (802.11n)'; " +
            "elif [ -n \"$freq\" ] && [ \"$freq\" -ge 5000 ] 2>/dev/null; then wifi_std='Wi-Fi 5 (802.11ac)'; " +
            "elif [ -n \"$freq\" ] && [ \"$freq\" -lt 5000 ] 2>/dev/null; then " +
            "  rate_num=$(echo \"$rate\" | grep -oP '[\\d.]+' | head -1); " +
            "  if [ -n \"$rate_num\" ] && [ \"$(echo \"$rate_num > 54\" | bc 2>/dev/null)\" = '1' ]; then " +
            "    wifi_std='Wi-Fi 4 (802.11n)'; " +
            "  else wifi_std='802.11g'; fi; " +
            "fi; " +
            "echo \"SIGNAL=${signal:---}\"; " +
            "echo \"NOISE=${noise:---}\"; " +
            "echo \"RATE=${rate:---}\"; " +
            "echo \"BAND=${band:-}\"; " +
            "echo \"WIFI_STD=${wifi_std:-unknown}\""
        ]
        stdout: SplitParser { onRead: (line) => {
            let idx = line.indexOf("=");
            if (idx < 0) return;
            let key = line.substring(0, idx), val = line.substring(idx + 1).trim();
            if (key === "SIGNAL") {
                root._diagSignal = val;
                if (val !== "--") { let a = root._histSignal.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histSignal = a; }
            }
            else if (key === "NOISE") {
                root._diagNoise = val;
                if (val !== "--") { let a = root._histNoise.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histNoise = a; }
            }
            else if (key === "RATE") root._diagLinkRate = val;
            else if (key === "BAND") root._diagBand = val;
            else if (key === "WIFI_STD") root._diagWifiStandard = val;
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[wifi-info stderr]", line); } }
        onExited: (code, status) => {
            root._diagLoading = false;
            if (code !== 0) console.log("[wifi-info] exit", code);
        }
    }

    property Process gwPingProc: Process {
        running: false
        command: ["bash", "-c",
            "gw=$(ip route | awk '/default/{print $3; exit}'); " +
            "[ -z \"$gw\" ] && echo 'GW=--' && exit 0; " +
            "echo \"GW=$gw\"; " +
            "out=$(ping -c 5 -i 0.2 -W 1 \"$gw\" 2>/dev/null); " +
            "loss=$(echo \"$out\" | grep -oP '\\d+(?=% packet loss)'); " +
            "rtt=$(echo \"$out\" | grep -E 'rtt|round-trip'); " +
            "avg=$(echo \"$rtt\" | grep -oP '[\\d.]+' | sed -n '2p'); " +
            "jitter=$(echo \"$rtt\" | grep -oP '[\\d.]+' | sed -n '4p'); " +
            "echo \"GW_PING=${avg:---}\"; " +
            "echo \"GW_JITTER=${jitter:---}\"; " +
            "echo \"GW_LOSS=${loss:---}\""
        ]
        stdout: SplitParser { onRead: (line) => {
            let idx = line.indexOf("=");
            if (idx < 0) return;
            let key = line.substring(0, idx), val = line.substring(idx + 1).trim();
            if (key === "GW") root._diagGateway = val;
            else if (key === "GW_PING") {
                root._diagGwPing = val;
                if (val !== "--") { let a = root._histGwPing.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histGwPing = a; }
            }
            else if (key === "GW_JITTER") {
                root._diagGwJitter = val;
                if (val !== "--") { let a = root._histGwJitter.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histGwJitter = a; }
            }
            else if (key === "GW_LOSS") {
                root._diagGwLoss = val;
                if (val !== "--") { let a = root._histGwLoss.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histGwLoss = a; }
            }
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[gw-ping stderr]", line); } }
    }

    property Process netPingProc: Process {
        running: false
        command: ["bash", "-c",
            "out=$(ping -c 5 -i 0.2 -W 1 1.1.1.1 2>/dev/null); " +
            "loss=$(echo \"$out\" | grep -oP '\\d+(?=% packet loss)'); " +
            "rtt=$(echo \"$out\" | grep -E 'rtt|round-trip'); " +
            "avg=$(echo \"$rtt\" | grep -oP '[\\d.]+' | sed -n '2p'); " +
            "jitter=$(echo \"$rtt\" | grep -oP '[\\d.]+' | sed -n '4p'); " +
            "echo \"NET_PING=${avg:---}\"; " +
            "echo \"NET_JITTER=${jitter:---}\"; " +
            "echo \"NET_LOSS=${loss:---}\""
        ]
        stdout: SplitParser { onRead: (line) => {
            let idx = line.indexOf("=");
            if (idx < 0) return;
            let key = line.substring(0, idx), val = line.substring(idx + 1).trim();
            if (key === "NET_PING") {
                root._diagNetPing = val;
                if (val !== "--") { let a = root._histNetPing.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histNetPing = a; }
            }
            else if (key === "NET_JITTER") {
                root._diagNetJitter = val;
                if (val !== "--") { let a = root._histNetJitter.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histNetJitter = a; }
            }
            else if (key === "NET_LOSS") {
                root._diagNetLoss = val;
                if (val !== "--") { let a = root._histNetLoss.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histNetLoss = a; }
            }
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[net-ping stderr]", line); } }
    }

    property Process dnsProc: Process {
        running: false
        command: ["bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi' | head -1 | cut -d: -f1); " +
            "dns=$(nmcli -t -f IP4.DNS dev show \"$iface\" 2>/dev/null | head -1 | cut -d: -f2); " +
            "echo \"DNS_SERVER=${dns:---}\"; " +
            "start=$(date +%s%3N); " +
            "getent hosts example.com >/dev/null 2>&1 || true; " +
            "end=$(date +%s%3N); " +
            "elapsed=$((end - start)); " +
            "echo \"DNS_TIME=${elapsed}\""
        ]
        stdout: SplitParser { onRead: (line) => {
            let idx = line.indexOf("=");
            if (idx < 0) return;
            let key = line.substring(0, idx), val = line.substring(idx + 1).trim();
            if (key === "DNS_SERVER") root._diagDnsServer = val;
            else if (key === "DNS_TIME") {
                root._diagDnsTime = val;
                if (val !== "--") { let a = root._histDnsTime.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); root._histDnsTime = a; }
            }
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[dns stderr]", line); } }
    }

    property Process speedTestProc: Process {
        running: false
        command: ["bash", "-c",
            "gw=$(ip route | awk '/default/{print $3; exit}'); " +
            // Baseline: ping the router before load
            "base_out=$(ping -c 5 -i 0.2 -W 1 \"$gw\" 2>/dev/null); " +
            "base_avg=$(echo \"$base_out\" | grep -E 'rtt|round-trip' | grep -oP '[\\d.]+' | sed -n '2p'); " +
            "[ -z \"$base_avg\" ] && base_avg=0; " +
            // Download test with concurrent router ping
            "ping -c 30 -i 0.5 -W 1 \"$gw\" > /tmp/whyfi_load_ping 2>/dev/null & " +
            "ping_pid=$!; " +
            "down_bps=$(curl -o /dev/null -w '%{speed_download}' -s --max-time 15 " +
            "'https://speed.cloudflare.com/__down?bytes=10000000'); " +
            "down_mbps=$(echo \"scale=1; $down_bps * 8 / 1000000\" | bc 2>/dev/null); " +
            "echo \"DOWN=${down_mbps:---}\"; " +
            // Upload test (continues while ping runs)
            "tmpf=$(mktemp); " +
            "dd if=/dev/zero of=\"$tmpf\" bs=1M count=5 2>/dev/null; " +
            "up_bps=$(curl -X POST -w '%{speed_upload}' -s --max-time 15 " +
            "--data-binary @\"$tmpf\" " +
            "-H 'Content-Type: application/octet-stream' " +
            "'https://speed.cloudflare.com/__up'); " +
            "rm -f \"$tmpf\"; " +
            "up_mbps=$(echo \"scale=1; $up_bps * 8 / 1000000\" | bc 2>/dev/null); " +
            "echo \"UP=${up_mbps:---}\"; " +
            // Stop the background ping, analyze results
            "kill $ping_pid 2>/dev/null; wait $ping_pid 2>/dev/null; " +
            "load_out=$(cat /tmp/whyfi_load_ping 2>/dev/null); " +
            "rm -f /tmp/whyfi_load_ping; " +
            "load_avg=$(echo \"$load_out\" | grep -E 'rtt|round-trip' | grep -oP '[\\d.]+' | sed -n '2p'); " +
            "[ -z \"$load_avg\" ] && load_avg=0; " +
            // Calculate bloat ratio
            "if [ \"$base_avg\" != '0' ] && [ \"$load_avg\" != '0' ]; then " +
            "  ratio=$(echo \"scale=1; $load_avg / $base_avg\" | bc 2>/dev/null); " +
            "  echo \"BLOAT_BASE=$base_avg\"; " +
            "  echo \"BLOAT_LOAD=$load_avg\"; " +
            "  echo \"BLOAT_RATIO=$ratio\"; " +
            "else " +
            "  echo \"BLOAT_BASE=--\"; " +
            "  echo \"BLOAT_LOAD=--\"; " +
            "  echo \"BLOAT_RATIO=--\"; " +
            "fi"
        ]
        stdout: SplitParser { onRead: (line) => {
            let idx = line.indexOf("=");
            if (idx < 0) return;
            let key = line.substring(0, idx), val = line.substring(idx + 1).trim();
            if (key === "DOWN") root._diagDownload = val;
            else if (key === "UP") root._diagUpload = val;
            else if (key === "BLOAT_BASE") root._bloatBase = val;
            else if (key === "BLOAT_LOAD") root._bloatLoad = val;
            else if (key === "BLOAT_RATIO") {
                let ratio = parseFloat(val);
                let base = root._bloatBase;
                let load = root._bloatLoad;
                if (!isNaN(ratio) && base !== "--" && load !== "--") {
                    if (ratio < 3.0) {
                        root._diagBufferbloat = "Router stayed responsive (" + base + "ms \u2192 " + load + "ms) \u2014 no bufferbloat.";
                        root._diagBufferbloatOk = true;
                    } else {
                        root._diagBufferbloat = "Lag under load: router ping spiked from " + base + "ms to " + load + "ms (" + val + "x). This causes lag for everyone on the network during heavy usage.";
                        root._diagBufferbloatOk = false;
                    }
                } else {
                    root._diagBufferbloat = "";
                }
            }
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[speedtest stderr]", line); } }
        onExited: { root._speedTestRunning = false; }
    }

    // ── Captive portal processes ──────────────────────────────

    property Process connectivityProc: Process {
        running: false
        command: ["nmcli", "networking", "connectivity", "check"]
        stdout: SplitParser { onRead: (line) => {
            root._connectivityState = line.trim();
        }}
    }

    property Process captiveOpenProc: Process {
        running: false
        command: ["bash", "-c",
            "if command -v captive-browser &>/dev/null; then " +
            "  captive-browser; " +
            "else " +
            "  xdg-open 'http://detectportal.firefox.com/canonical.html'; " +
            "fi"
        ]
    }

    // ── Channel scanner process ───────────────────────────────

    property Process channelScanProc: Process {
        running: false
        command: ["bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi' | head -1 | cut -d: -f1); " +
            "nmcli -t -f SSID,CHAN,FREQ,SIGNAL,IN-USE dev wifi list ifname \"$iface\" --rescan yes"
        ]
        stdout: SplitParser { onRead: (line) => {
            let p = root.parseNmcli(line);
            if (p.length < 5) return;
            let ssid = p[0] || "(hidden)";
            let chan = p[1];
            let freq = parseInt(p[2]) || 0;
            let sig = p[3];
            let inUse = p[4] === "*";
            let band = freq < 3000 ? "2.4" : (freq < 6000 ? "5" : "6");

            if (inUse) { root._currentChannel = chan; root._currentBand = band; }

            let key = chan + "-" + band;
            if (!root._chanMap[key]) {
                root._chanMap[key] = { channel: parseInt(chan) || 0, band: band, networks: [], isOurs: false };
            }
            root._chanMap[key].networks.push(ssid + " (" + sig + "%)");
            if (inUse) root._chanMap[key].isOurs = true;
        }}
        onExited: {
            let map = root._chanMap;
            let keys = Object.keys(map).sort((a, b) => map[a].channel - map[b].channel);
            for (let k of keys) {
                let entry = map[k];
                root.channelModel.append({
                    channel: entry.channel,
                    band: entry.band,
                    networks: entry.networks.join(", "),
                    count: entry.networks.length,
                    isOurs: entry.isOurs
                });
            }
            root._chanMap = {};
        }
    }

    // ── DNS switching processes ────────────────────────────────

    property Process dnsSwitchProc: Process {
        running: false
        onExited: (code, status) => {
            if (code === 0) {
                root.dnsReconnectProc.command = ["nmcli", "con", "up", "uuid", root._connectedConnectionUuid];
                root.dnsReconnectProc.running = true;
            } else {
                console.log("[dns-switch] failed, exit", code);
            }
        }
    }

    property Process dnsReconnectProc: Process {
        running: false
        onExited: {
            root.dnsProc.running = true;
        }
    }

    // ── Export process ─────────────────────────────────────────

    property Process exportProc: Process {
        running: false
        onExited: (code, status) => {
            if (code === 0) {
                root._exportCopied = true;
                root.exportResetTimer.start();
            }
        }
    }

    // ── Timers ────────────────────────────────────────────────

    property Timer exportResetTimer: Timer {
        interval: 2000
        onTriggered: root._exportCopied = false
    }

    property Timer summaryTimer: Timer {
        interval: 10000
        repeat: true
        running: true
        onTriggered: root.refreshSummary()
    }

    property Timer diagTimer: Timer {
        interval: 2000; repeat: true
        running: root._diagPolling
        onTriggered: {
            if (!root.wifiInfoProc.running) root.wifiInfoProc.running = true;
            if (!root.gwPingProc.running) root.gwPingProc.running = true;
            if (!root.netPingProc.running) root.netPingProc.running = true;
            if (!root.dnsProc.running) root.dnsProc.running = true;
        }
    }
}
