import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components" as Components
import "wifi"

PanelWindow {
    id: wifiPop
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:wifi"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property string connectedSsid: ""
    property string connectedConnectionId: ""
    property string connectedConnectionUuid: ""
    ListModel { id: netModel }
    ListModel { id: knownModel }

    property string popupState: "list"   // list | detail | password | enterprise | connecting | diagnostics | channels
    property string targetSsid: ""
    property string targetSecurity: ""
    property int    targetSignal: 0
    property bool   targetIsConnected: false
    property bool   targetIsKnown: false
    property string targetConnectionId: ""
    property string targetConnectionUuid: ""
    property string connectError: ""

    // Detail view info
    property string detailIp: ""
    property string detailGateway: ""
    property string detailDns: ""
    property string detailFreq: ""

    // ── Diagnostics state ──
    property bool diagLoading: false
    property bool speedTestRunning: false

    property string diagBand: ""
    property string diagSignal: ""
    property string diagNoise: ""
    property string diagLinkRate: ""
    property string diagGateway: ""
    property string diagGwPing: ""
    property string diagGwJitter: ""
    property string diagGwLoss: ""
    property string diagNetPing: ""
    property string diagNetJitter: ""
    property string diagNetLoss: ""
    property string diagDnsServer: ""
    property string diagDnsTime: ""
    property string diagDownload: ""
    property string diagUpload: ""
    property string diagBufferbloat: ""
    property bool diagBufferbloatOk: true
    property string _bloatBase: ""
    property string _bloatLoad: ""
    property string diagWifiStandard: ""

    // ── Captive portal state ──
    property string connectivityState: ""  // "full", "portal", "limited", "none", "unknown"
    property bool isCaptivePortal: connectivityState === "portal" || connectivityState === "limited"

    // ── Channel scanner state ──
    property string currentChannel: ""
    property string currentBand: ""
    ListModel { id: channelModel }
    property bool listLoading: popupState === "list" && scanProc.running && netModel.count === 0
    property bool channelLoading: popupState === "channels" && channelScanProc.running

    // ── Export state ──
    property bool exportCopied: false

    // Sparkline history arrays (last 30 samples)
    property var histSignal: []
    property var histNoise: []
    property var histGwPing: []
    property var histGwJitter: []
    property var histGwLoss: []
    property var histNetPing: []
    property var histNetJitter: []
    property var histNetLoss: []
    property var histDnsTime: []

    function preparePanelForOpen() {
        let item = wifiContentLoader.item;
        if (!item)
            return false;

        item.opacity = 0;
        item.scale = 0.92;
        return true;
    }

    onActiveChanged: {
        if (active) {
            contentLoaded = true;
            if (preparePanelForOpen())
                wifiOpenAnim.start();
            resetState(); scan(); loadKnown();
        } else if (!closing) {
            if (wifiContentLoader.item) {
                closing = true;
                wifiCloseAnim.start();
            } else {
                closing = false;
            }
        }
    }

    SequentialAnimation {
        id: wifiOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: wifiContentLoader.item
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            Components.Anim {
                target: wifiContentLoader.item
                property: "scale"
                to: 1.0
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
        }
    }
    SequentialAnimation {
        id: wifiCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: wifiContentLoader.item
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: wifiContentLoader.item
                property: "scale"
                to: 0.92
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { wifiPop.closing = false; } }
    }

    function resetState() {
        popupState = "list"; targetSsid = ""; targetSecurity = ""; targetSignal = 0;
        targetIsConnected = false; targetIsKnown = false; connectError = "";
        targetConnectionId = ""; targetConnectionUuid = "";
        detailIp = ""; detailGateway = ""; detailDns = ""; detailFreq = "";
        diagLoading = false; speedTestRunning = false;
    }

    function scan() {
        netModel.clear();
        connectedSsid = "";
        connectedConnectionId = "";
        connectedConnectionUuid = "";
        scanProc.running = true;
        connectivityProc.running = true;
    }
    function loadKnown() { knownModel.clear(); knownProc.running = true; }

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
        if (connectedSsid === ssid && connectedConnectionId !== "")
            return connectedConnectionId;
        let entry = knownConnection(ssid);
        return entry ? (entry.id || "") : "";
    }

    function connectionUuidForSsid(ssid) {
        if (connectedSsid === ssid && connectedConnectionUuid !== "")
            return connectedConnectionUuid;
        let entry = knownConnection(ssid);
        return entry ? (entry.uuid || "") : "";
    }

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

    // ── Actions ───────────────────────────────────────────────

    function connectTo(ssid, security) {
        connectError = "";
        if (isEnterprise(security)) {
            targetSsid = ssid;
            targetSecurity = security;
            targetConnectionId = connectionIdForSsid(ssid);
            targetConnectionUuid = connectionUuidForSsid(ssid);
            popupState = "enterprise";
        } else if (isKnown(ssid)) {
            let uuid = connectionUuidForSsid(ssid);
            let id = connectionIdForSsid(ssid);
            popupState = "connecting";
            targetSsid = ssid;
            if (uuid !== "")
                connectProc.command = ["nmcli", "con", "up", "uuid", uuid];
            else
                connectProc.command = ["nmcli", "con", "up", "id", id];
            connectProc.running = true;
        } else if (security !== "") {
            targetSsid = ssid;
            targetSecurity = security;
            popupState = "password";
        } else {
            popupState = "connecting"; targetSsid = ssid;
            connectProc.command = ["nmcli", "dev", "wifi", "connect", ssid];
            connectProc.running = true;
        }
    }

    function submitPassword(password) {
        if (!password) return;
        popupState = "connecting";
        connectProc.command = ["nmcli", "dev", "wifi", "connect", targetSsid, "password", password];
        connectProc.running = true;
    }

    function submitEnterprise(identity, password) {
        if (!identity || !password) return;
        popupState = "connecting";
        // Inline the enterprise connect logic — each arg is a separate array element
        // so spaces in identity/password are preserved as proper positional parameters.
        enterpriseProc.command = [
            "bash", "-c",
            'iface=$(nmcli -t -f DEVICE,TYPE dev | grep ":wifi$" | head -1 | cut -d: -f1); ' +
            'if [ -n "$4" ]; then nmcli connection delete uuid "$4" 2>/dev/null; ' +
            'elif [ -n "$5" ]; then nmcli connection delete id "$5" 2>/dev/null; fi; ' +
            'nmcli connection add type wifi ifname "$iface" con-name "$1" ssid "$1" ' +
            'wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 ' +
            '802-1x.identity "$2" 802-1x.password "$3" && ' +
            'nmcli connection up id "$1"',
            "--", targetSsid, identity, password, targetConnectionUuid, targetConnectionId
        ];
        enterpriseProc.running = true;
    }

    function disconnect() {
        if (connectedConnectionUuid === "") return;
        disconnectProc.command = ["nmcli", "con", "down", "uuid", connectedConnectionUuid];
        disconnectProc.running = true;
    }

    function forgetNetwork() {
        let uuid = targetConnectionUuid;
        let id = targetConnectionId;
        if (uuid !== "")
            forgetProc.command = ["nmcli", "con", "delete", "uuid", uuid];
        else if (id !== "")
            forgetProc.command = ["nmcli", "con", "delete", "id", id];
        else
            return;
        forgetProc.running = true;
    }

    function openDetail(ssid, security, signal, isActive) {
        targetSsid = ssid; targetSecurity = security; targetSignal = signal;
        targetConnectionId = connectionIdForSsid(ssid);
        targetConnectionUuid = connectionUuidForSsid(ssid);
        targetIsConnected = isActive;
        targetIsKnown = targetConnectionId !== "" || targetConnectionUuid !== "";
        detailIp = ""; detailGateway = ""; detailDns = ""; detailFreq = "";
        connectError = "";
        popupState = "detail";
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
                "--", ssid, targetConnectionUuid, targetConnectionId
            ];
            detailProc.running = true;
        }
    }

    function startDiagnostics() {
        diagBand = ""; diagSignal = ""; diagNoise = ""; diagLinkRate = "";
        diagGateway = ""; diagGwPing = ""; diagGwJitter = ""; diagGwLoss = "";
        diagNetPing = ""; diagNetJitter = ""; diagNetLoss = "";
        diagDnsServer = ""; diagDnsTime = "";
        diagDownload = ""; diagUpload = "";
        diagBufferbloat = ""; diagBufferbloatOk = true; _bloatBase = ""; _bloatLoad = "";
        diagWifiStandard = "";
        histSignal = []; histNoise = [];
        histGwPing = []; histGwJitter = []; histGwLoss = [];
        histNetPing = []; histNetJitter = []; histNetLoss = [];
        histDnsTime = [];
        diagLoading = true; speedTestRunning = false;
        popupState = "diagnostics";
        wifiInfoProc.running = true;
        gwPingProc.running = true;
        netPingProc.running = true;
        dnsProc.running = true;
    }

    function signalColor(dbm) {
        let v = parseInt(dbm);
        if (isNaN(v)) return Theme.fg4;
        if (v >= -50) return Theme.greenBright;
        if (v >= -70) return Theme.yellowBright;
        return Theme.redBright;
    }
    function pingColor(ms) {
        let v = parseFloat(ms);
        if (isNaN(v)) return Theme.fg4;
        if (v < 20) return Theme.greenBright;
        if (v < 50) return Theme.yellowBright;
        return Theme.redBright;
    }
    function lossColor(pct) {
        let v = parseFloat(pct);
        if (isNaN(v)) return Theme.fg4;
        if (v === 0) return Theme.greenBright;
        if (v <= 2) return Theme.yellowBright;
        return Theme.redBright;
    }

    function startChannelScan() {
        channelModel.clear();
        currentChannel = ""; currentBand = "";
        popupState = "channels";
        channelScanProc.running = true;
    }

    function switchDns(server) {
        if (connectedConnectionUuid === "") return;
        if (server === "auto") {
            dnsSwitchProc.command = ["nmcli", "con", "mod", "uuid", connectedConnectionUuid, "ipv4.dns", "", "ipv4.ignore-auto-dns", "no"];
        } else {
            dnsSwitchProc.command = ["nmcli", "con", "mod", "uuid", connectedConnectionUuid, "ipv4.dns", server, "ipv4.ignore-auto-dns", "yes"];
        }
        dnsSwitchProc.running = true;
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
        report += "  SSID: " + connectedSsid + "\n";
        report += "  Band: " + (diagBand || "--") + "\n";
        report += "  Standard: " + (diagWifiStandard || "--") + "\n";
        report += "  Channel: " + (currentChannel || "--") + "\n\n";

        report += "SIGNAL\n";
        report += "  " + colorLabel(diagSignal, -50, -70, false) + " Signal: " + (diagSignal !== "" && diagSignal !== "--" ? diagSignal + " dBm" : "--") + "\n";
        report += "  Noise: " + (diagNoise !== "" && diagNoise !== "--" ? diagNoise + " dBm" : "--") + "\n";
        report += "  Link Rate: " + (diagLinkRate !== "" && diagLinkRate !== "--" ? diagLinkRate + " Mbps" : "--") + "\n\n";

        report += "ROUTER \u00B7 " + (diagGateway || "--") + "\n";
        report += "  " + colorLabel(diagGwPing, 10, 50, true) + " Ping: " + (diagGwPing !== "" && diagGwPing !== "--" ? diagGwPing + " ms" : "--") + "\n";
        report += "  " + colorLabel(diagGwJitter, 5, 20, true) + " Jitter: " + (diagGwJitter !== "" && diagGwJitter !== "--" ? diagGwJitter + " ms" : "--") + "\n";
        report += "  " + colorLabel(diagGwLoss, 0, 2, true) + " Loss: " + (diagGwLoss !== "" && diagGwLoss !== "--" ? diagGwLoss + "%" : "--") + "\n\n";

        report += "INTERNET \u00B7 1.1.1.1\n";
        report += "  " + colorLabel(diagNetPing, 20, 50, true) + " Ping: " + (diagNetPing !== "" && diagNetPing !== "--" ? diagNetPing + " ms" : "--") + "\n";
        report += "  " + colorLabel(diagNetJitter, 10, 30, true) + " Jitter: " + (diagNetJitter !== "" && diagNetJitter !== "--" ? diagNetJitter + " ms" : "--") + "\n";
        report += "  " + colorLabel(diagNetLoss, 0, 2, true) + " Loss: " + (diagNetLoss !== "" && diagNetLoss !== "--" ? diagNetLoss + "%" : "--") + "\n\n";

        report += "DNS \u00B7 " + (diagDnsServer || "--") + "\n";
        report += "  " + colorLabel(diagDnsTime, 30, 100, true) + " Lookup: " + (diagDnsTime !== "" && diagDnsTime !== "--" ? diagDnsTime + " ms" : "--") + "\n\n";

        if (diagDownload !== "") {
            report += "SPEED TEST\n";
            report += "  Download: " + diagDownload + " Mbps\n";
            report += "  Upload: " + diagUpload + " Mbps\n";
            if (diagBufferbloat !== "") {
                report += "  " + (diagBufferbloatOk ? "\uD83D\uDFE2" : "\uD83D\uDD34") + " " + diagBufferbloat + "\n";
            }
            report += "\n";
        }

        report += "Paste this into ChatGPT or Claude for help diagnosing issues.";

        exportProc.command = ["bash", "-c", "printf '%s' \"$1\" | wl-copy", "--", report];
        exportProc.running = true;
    }

    function qualityScore() {
        let score = 100;
        let hasData = false;

        let sig = parseInt(diagSignal);
        if (!isNaN(sig)) {
            hasData = true;
            let sigScore = Math.max(0, Math.min(100, ((sig + 90) / 60) * 100));
            score = Math.min(score, sigScore);
        }

        let gwP = parseFloat(diagGwPing);
        if (!isNaN(gwP)) {
            hasData = true;
            let pingScore = Math.max(0, Math.min(100, 100 - gwP));
            score = Math.min(score, pingScore);
        }

        let netP = parseFloat(diagNetPing);
        if (!isNaN(netP)) {
            hasData = true;
            let netScore = Math.max(0, Math.min(100, 100 - (netP / 2)));
            score = Math.min(score, netScore);
        }

        let gwL = parseFloat(diagGwLoss);
        if (!isNaN(gwL) && gwL > 0) {
            hasData = true;
            score = Math.min(score, Math.max(0, 100 - gwL * 20));
        }
        let netL = parseFloat(diagNetLoss);
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
        if (score < 0) return Theme.fg4;
        if (score >= 80) return Theme.greenBright;
        if (score >= 60) return Theme.aquaBright;
        if (score >= 40) return Theme.yellowBright;
        return Theme.redBright;
    }

    // ── Processes ─────────────────────────────────────────────
    Process {
        id: scanProc
        command: [
            "bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1); " +
            "nmcli -t -f SSID,SIGNAL,SECURITY,IN-USE dev wifi list ifname \"$iface\" --rescan yes"
        ]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let p = wifiPop.parseNmcli(line);
            if (p.length < 4 || !p[0]) return;
            let isActive = p[3] === "*";
            let sig = parseInt(p[1]) || 0;
            if (isActive) wifiPop.connectedSsid = p[0];
            for (let i = 0; i < netModel.count; i++) {
                if (netModel.get(i).ssid === p[0]) {
                    if (isActive || sig > netModel.get(i).signal)
                        netModel.set(i, { ssid: p[0], signal: Math.max(sig, netModel.get(i).signal), security: p[2] || "", active: isActive || netModel.get(i).active });
                    return;
                }
            }
            netModel.append({ ssid: p[0], signal: sig, security: p[2] || "", active: isActive });
        } }
        onExited: (code, status) => { activeProc.running = true; }
    }

    Process {
        id: knownProc
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
            let parts = wifiPop.parseNmcli(line);
            if (parts.length < 3) return;
            knownModel.append({
                id: parts[0],
                uuid: parts[1],
                ssid: parts[2] || parts[0]
            });
        } }
    }

    Process {
        id: activeProc
        command: ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE", "con", "show", "--active"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let parts = wifiPop.parseNmcli(line);
            if (parts.length >= 4 && parts[2] === "802-11-wireless") {
                let ssid = wifiPop.connectedSsid || parts[0];
                if (wifiPop.connectedSsid === "")
                    wifiPop.connectedSsid = ssid;
                wifiPop.connectedConnectionId = parts[0] || "";
                wifiPop.connectedConnectionUuid = parts[1] || "";
                for (let i = 0; i < netModel.count; i++) {
                    if (netModel.get(i).ssid === ssid) {
                        netModel.setProperty(i, "active", true);
                        return;
                    }
                }
            }
        } }
    }

    Process {
        id: connectProc; running: false
        onExited: (code, status) => {
            if (code === 0) { wifiPop.resetState(); wifiPop.scan(); wifiPop.loadKnown(); }
            else { wifiPop.connectError = "Connection failed (exit " + code + ")"; wifiPop.popupState = "list"; }
        }
    }

    Process {
        id: enterpriseProc; running: false
        onExited: (code, status) => {
            if (code === 0) { wifiPop.resetState(); wifiPop.scan(); wifiPop.loadKnown(); }
            else { wifiPop.connectError = "Enterprise auth failed (exit " + code + ")"; wifiPop.popupState = "list"; }
        }
    }

    Process {
        id: disconnectProc; running: false
        // command set dynamically in disconnect()
        onExited: (code, status) => {
            wifiPop.connectedSsid = "";
            wifiPop.connectedConnectionId = "";
            wifiPop.connectedConnectionUuid = "";
            wifiPop.resetState(); wifiPop.scan();
        }
    }

    Process {
        id: forgetProc; running: false
        // command set dynamically in forgetNetwork()
        onExited: (code, status) => {
            wifiPop.resetState(); wifiPop.scan(); wifiPop.loadKnown();
        }
    }

    Process {
        id: detailProc; running: false
        stdout: SplitParser { onRead: (line) => {
            if (line.startsWith("IP|"))   wifiPop.detailIp      = line.substring(3).trim();
            if (line.startsWith("GW|"))   wifiPop.detailGateway  = line.substring(3).trim();
            if (line.startsWith("DNS|"))  wifiPop.detailDns      = line.substring(4).trim();
            if (line.startsWith("FREQ|")) wifiPop.detailFreq     = line.substring(5).trim();
        } }
    }

    // ── Diagnostics processes ─────────────────────────────────
    Process {
        id: wifiInfoProc; running: false
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
                wifiPop.diagSignal = val;
                if (val !== "--") { let a = wifiPop.histSignal.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histSignal = a; }
            }
            else if (key === "NOISE") {
                wifiPop.diagNoise = val;
                if (val !== "--") { let a = wifiPop.histNoise.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histNoise = a; }
            }
            else if (key === "RATE") wifiPop.diagLinkRate = val;
            else if (key === "BAND") wifiPop.diagBand = val;
            else if (key === "WIFI_STD") wifiPop.diagWifiStandard = val;
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[wifi-info stderr]", line); } }
        onExited: (code, status) => {
            wifiPop.diagLoading = false;
            if (code !== 0) console.log("[wifi-info] exit", code);
        }
    }

    Process {
        id: gwPingProc; running: false
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
            if (key === "GW") wifiPop.diagGateway = val;
            else if (key === "GW_PING") {
                wifiPop.diagGwPing = val;
                if (val !== "--") { let a = wifiPop.histGwPing.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histGwPing = a; }
            }
            else if (key === "GW_JITTER") {
                wifiPop.diagGwJitter = val;
                if (val !== "--") { let a = wifiPop.histGwJitter.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histGwJitter = a; }
            }
            else if (key === "GW_LOSS") {
                wifiPop.diagGwLoss = val;
                if (val !== "--") { let a = wifiPop.histGwLoss.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histGwLoss = a; }
            }
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[gw-ping stderr]", line); } }
    }

    Process {
        id: netPingProc; running: false
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
                wifiPop.diagNetPing = val;
                if (val !== "--") { let a = wifiPop.histNetPing.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histNetPing = a; }
            }
            else if (key === "NET_JITTER") {
                wifiPop.diagNetJitter = val;
                if (val !== "--") { let a = wifiPop.histNetJitter.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histNetJitter = a; }
            }
            else if (key === "NET_LOSS") {
                wifiPop.diagNetLoss = val;
                if (val !== "--") { let a = wifiPop.histNetLoss.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histNetLoss = a; }
            }
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[net-ping stderr]", line); } }
    }

    Process {
        id: dnsProc; running: false
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
            if (key === "DNS_SERVER") wifiPop.diagDnsServer = val;
            else if (key === "DNS_TIME") {
                wifiPop.diagDnsTime = val;
                if (val !== "--") { let a = wifiPop.histDnsTime.slice(); a.push(parseFloat(val)); if (a.length > 30) a.shift(); wifiPop.histDnsTime = a; }
            }
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[dns stderr]", line); } }
    }

    Process {
        id: speedTestProc; running: false
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
            if (key === "DOWN") wifiPop.diagDownload = val;
            else if (key === "UP") wifiPop.diagUpload = val;
            else if (key === "BLOAT_BASE") wifiPop._bloatBase = val;
            else if (key === "BLOAT_LOAD") wifiPop._bloatLoad = val;
            else if (key === "BLOAT_RATIO") {
                let ratio = parseFloat(val);
                let base = wifiPop._bloatBase;
                let load = wifiPop._bloatLoad;
                if (!isNaN(ratio) && base !== "--" && load !== "--") {
                    if (ratio < 3.0) {
                        wifiPop.diagBufferbloat = "Router stayed responsive (" + base + "ms \u2192 " + load + "ms) \u2014 no bufferbloat.";
                        wifiPop.diagBufferbloatOk = true;
                    } else {
                        wifiPop.diagBufferbloat = "Lag under load: router ping spiked from " + base + "ms to " + load + "ms (" + val + "x). This causes lag for everyone on the network during heavy usage.";
                        wifiPop.diagBufferbloatOk = false;
                    }
                } else {
                    wifiPop.diagBufferbloat = "";
                }
            }
        }}
        stderr: SplitParser { onRead: (line) => { console.log("[speedtest stderr]", line); } }
        onExited: { wifiPop.speedTestRunning = false; }
    }

    // ── Captive portal processes ────────────────────────────────
    Process {
        id: connectivityProc; running: false
        command: ["nmcli", "networking", "connectivity", "check"]
        stdout: SplitParser { onRead: (line) => {
            wifiPop.connectivityState = line.trim();
        }}
    }

    Process {
        id: captiveOpenProc; running: false
        command: ["bash", "-c",
            "if command -v captive-browser &>/dev/null; then " +
            "  captive-browser; " +
            "else " +
            "  xdg-open 'http://detectportal.firefox.com/canonical.html'; " +
            "fi"
        ]
    }

    // ── Channel scanner process ─────────────────────────────────
    Process {
        id: channelScanProc; running: false
        property var _chanMap: ({})
        command: ["bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi' | head -1 | cut -d: -f1); " +
            "nmcli -t -f SSID,CHAN,FREQ,SIGNAL,IN-USE dev wifi list ifname \"$iface\" --rescan yes"
        ]
        stdout: SplitParser { onRead: (line) => {
            let p = wifiPop.parseNmcli(line);
            if (p.length < 5) return;
            let ssid = p[0] || "(hidden)";
            let chan = p[1];
            let freq = parseInt(p[2]) || 0;
            let sig = p[3];
            let inUse = p[4] === "*";
            let band = freq < 3000 ? "2.4" : (freq < 6000 ? "5" : "6");

            if (inUse) { wifiPop.currentChannel = chan; wifiPop.currentBand = band; }

            let key = chan + "-" + band;
            if (!channelScanProc._chanMap[key]) {
                channelScanProc._chanMap[key] = { channel: parseInt(chan) || 0, band: band, networks: [], isOurs: false };
            }
            channelScanProc._chanMap[key].networks.push(ssid + " (" + sig + "%)");
            if (inUse) channelScanProc._chanMap[key].isOurs = true;
        }}
        onExited: {
            let map = _chanMap;
            let keys = Object.keys(map).sort((a, b) => map[a].channel - map[b].channel);
            for (let k of keys) {
                let entry = map[k];
                channelModel.append({
                    channel: entry.channel,
                    band: entry.band,
                    networks: entry.networks.join(", "),
                    count: entry.networks.length,
                    isOurs: entry.isOurs
                });
            }
            _chanMap = {};
        }
    }

    // ── DNS switching processes ──────────────────────────────────
    Process {
        id: dnsSwitchProc; running: false
        onExited: (code, status) => {
            if (code === 0) {
                dnsReconnectProc.command = ["nmcli", "con", "up", "uuid", wifiPop.connectedConnectionUuid];
                dnsReconnectProc.running = true;
            } else {
                console.log("[dns-switch] failed, exit", code);
            }
        }
    }

    Process {
        id: dnsReconnectProc; running: false
        onExited: {
            dnsProc.running = true;
        }
    }

    // ── Export process ──────────────────────────────────────────
    Process {
        id: exportProc; running: false
        onExited: (code, status) => {
            if (code === 0) {
                wifiPop.exportCopied = true;
                exportResetTimer.start();
            }
        }
    }

    Timer {
        id: exportResetTimer; interval: 2000
        onTriggered: wifiPop.exportCopied = false
    }

    // ── Diagnostics polling timer ─────────────────────────────
    Timer {
        id: diagTimer; interval: 2000; repeat: true
        running: wifiPop.popupState === "diagnostics"
        onTriggered: {
            if (!wifiInfoProc.running) wifiInfoProc.running = true;
            if (!gwPingProc.running) gwPingProc.running = true;
            if (!netPingProc.running) netPingProc.running = true;
            if (!dnsProc.running) dnsProc.running = true;
        }
    }

    // ── Backdrop ──────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: {
            if (wifiPop.popupState !== "list") wifiPop.resetState();
            else wifiPop.close();
        }
        MouseArea { anchors.fill: parent; onClicked: wifiPop.close() }
    }

    Loader {
        id: wifiContentLoader
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth
        height: item ? item.implicitHeight : 0
        active: wifiPop.contentLoaded || wifiPop.active || wifiPop.closing
        asynchronous: true
        sourceComponent: wifiPanelComponent

        onLoaded: {
            item.opacity = 0;
            item.scale = 0.92;
            if (wifiPop.active)
                wifiOpenAnim.start();
        }
    }

    Component {
        id: wifiPanelComponent

        // ── Popup card ────────────────────────────────────────────
        Rectangle {
            id: wifiPanel
            anchors.fill: parent
            implicitHeight: wifiCol.implicitHeight + Theme.popupPadding * 2
            radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
            opacity: 0; scale: 0.92
            transformOrigin: Item.TopRight
            Behavior on height {
                Components.Anim {
                    duration: Theme.animHeightResize
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveStandard
                }
            }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: wifiCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 8

            // ── Header ────────────────────────────────────────
            RowLayout { Layout.fillWidth: true
                Text {
                    text: {
                        if (wifiPop.popupState === "detail")      return "󰖩  " + wifiPop.targetSsid;
                        if (wifiPop.popupState === "password")    return "󰌾  Password";
                        if (wifiPop.popupState === "enterprise")  return "󱄤  Sign In";
                        if (wifiPop.popupState === "connecting")  return "󰖩  Connecting…";
                        if (wifiPop.popupState === "diagnostics") return "󰖩  Diagnostics";
                        if (wifiPop.popupState === "channels")    return "󰐻  Channels";
                        return "󰖩  Wi-Fi";
                    }
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                // Back button
                Rectangle {
                    visible: wifiPop.popupState !== "list" && wifiPop.popupState !== "connecting"
                    width: backLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: backA
                        color: Theme.bg2
                        hoverOpacity: 0.6
                        pressedOpacity: 0.9
                        pressedScale: 0.98
                        onClicked: {
                            if (wifiPop.popupState === "channels") wifiPop.popupState = "diagnostics";
                            else wifiPop.resetState();
                        }

                        Text { id: backLabel; anchors.centerIn: parent; text: "← Back"; color: backA.containsMouse ? Theme.blueBright : Theme.fg4
                            Behavior on color {
                                Components.CAnim {
                                    duration: Theme.animHover
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    }
                }
                // Rescan button (list only)
                Rectangle {
                    visible: wifiPop.popupState === "list"
                    width: rescanLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: rescanA
                        color: Theme.bg2
                        hoverOpacity: 0.6
                        pressedOpacity: 0.9
                        pressedScale: 0.98
                        onClicked: wifiPop.scan()

                        Text { id: rescanLabel; anchors.centerIn: parent; text: "Rescan"; color: rescanA.containsMouse ? Theme.blueBright : Theme.fg4
                            Behavior on color {
                                Components.CAnim {
                                    duration: Theme.animHover
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    }
                }
            }

            // ── Error message ─────────────────────────────────
            Item {
                Layout.fillWidth: true; visible: wifiPop.connectError !== ""
                implicitHeight: errorText.implicitHeight
                Text { id: errorText; width: parent.width
                    text: wifiPop.connectError; color: Theme.redBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    opacity: wifiPop.connectError !== "" ? 1 : 0
                    y: wifiPop.connectError !== "" ? 0 : 6
                    Behavior on opacity {
                        Components.Anim {
                            duration: Theme.animContentSwap
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    Behavior on y {
                        Components.Anim {
                            duration: Theme.animContentSwap
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── State views ──────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: netModel.count === 0 ? 144 : 170
                Layout.maximumHeight: 220
                visible: wifiPop.popupState === "list"
                opacity: wifiPop.popupState === "list" ? 1 : 0
                clip: true
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }

                WifiList {
                    anchors.fill: parent
                    opacity: wifiPop.listLoading ? 0 : 1
                    enabled: opacity > 0.01
                    Behavior on opacity {
                        Components.Anim {
                            duration: Theme.animContentSwap
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    netModel: netModel
                    connectedSsid: wifiPop.connectedSsid
                    isCaptivePortal: wifiPop.isCaptivePortal
                    onConnectRequested: (ssid, security) => wifiPop.connectTo(ssid, security)
                    onDetailRequested: (ssid, security, signal, isActive) => wifiPop.openDetail(ssid, security, signal, isActive)
                    onCaptiveLoginRequested: captiveOpenProc.running = true
                }

                Column {
                    anchors.fill: parent
                    anchors.topMargin: 4
                    spacing: 0
                    opacity: wifiPop.listLoading ? 1 : 0
                    visible: opacity > 0
                    z: 1
                    Behavior on opacity {
                        Components.Anim {
                            duration: Theme.animContentSwap
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }

                    Repeater {
                        model: ListModel {
                            ListElement { skelWidth: 120 }
                            ListElement { skelWidth: 90 }
                            ListElement { skelWidth: 150 }
                            ListElement { skelWidth: 105 }
                        }
                        delegate: Item {
                            required property int skelWidth
                            required property int index
                            width: parent.width
                            height: 36

                            RowLayout {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 8

                                Rectangle { width: 18; height: 18; radius: 9; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Item { Layout.fillWidth: true }
                                Rectangle { width: 10; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Rectangle { width: 28; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Rectangle { width: 24; height: 24; radius: 12; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                            }

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 120 }
                                Components.Anim { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                Components.Anim { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            WifiDetail {
                visible: wifiPop.popupState === "detail"
                opacity: wifiPop.popupState === "detail" ? 1 : 0
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }
                Layout.fillWidth: true
                targetSsid: wifiPop.targetSsid
                targetSecurity: wifiPop.targetSecurity
                targetSignal: wifiPop.targetSignal
                targetIsConnected: wifiPop.targetIsConnected
                targetIsKnown: wifiPop.targetIsKnown
                detailIp: wifiPop.detailIp
                detailGateway: wifiPop.detailGateway
                detailDns: wifiPop.detailDns
                detailFreq: wifiPop.detailFreq
                connectError: wifiPop.connectError
                onConnectRequested: (ssid, security) => wifiPop.connectTo(ssid, security)
                onDisconnectRequested: wifiPop.disconnect()
                onForgetRequested: wifiPop.forgetNetwork()
                onDiagnosticsRequested: wifiPop.startDiagnostics()
            }

            WifiPassword {
                visible: wifiPop.popupState === "password"
                opacity: wifiPop.popupState === "password" ? 1 : 0
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }
                Layout.fillWidth: true
                targetSsid: wifiPop.targetSsid
                connectError: wifiPop.connectError
                onPasswordSubmitted: (pw) => wifiPop.submitPassword(pw)
                onBackRequested: wifiPop.resetState()
            }

            WifiEnterprise {
                visible: wifiPop.popupState === "enterprise"
                opacity: wifiPop.popupState === "enterprise" ? 1 : 0
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }
                Layout.fillWidth: true
                targetSsid: wifiPop.targetSsid
                connectError: wifiPop.connectError
                onEnterpriseSubmitted: (identity, password) => wifiPop.submitEnterprise(identity, password)
                onBackRequested: wifiPop.resetState()
            }

            WifiConnecting {
                visible: wifiPop.popupState === "connecting"
                opacity: wifiPop.popupState === "connecting" ? 1 : 0
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }
                Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
                targetSsid: wifiPop.targetSsid
            }

            WifiDiagnostics {
                Layout.fillWidth: true; Layout.preferredHeight: 500; Layout.maximumHeight: 500
                visible: wifiPop.popupState === "diagnostics"
                opacity: wifiPop.popupState === "diagnostics" ? 1 : 0
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }
                diagLoading: wifiPop.diagLoading
                speedTestRunning: wifiPop.speedTestRunning
                connectedSsid: wifiPop.connectedSsid
                exportCopied: wifiPop.exportCopied
                diagBand: wifiPop.diagBand
                diagSignal: wifiPop.diagSignal
                diagNoise: wifiPop.diagNoise
                diagLinkRate: wifiPop.diagLinkRate
                diagGateway: wifiPop.diagGateway
                diagGwPing: wifiPop.diagGwPing
                diagGwJitter: wifiPop.diagGwJitter
                diagGwLoss: wifiPop.diagGwLoss
                diagNetPing: wifiPop.diagNetPing
                diagNetJitter: wifiPop.diagNetJitter
                diagNetLoss: wifiPop.diagNetLoss
                diagDnsServer: wifiPop.diagDnsServer
                diagDnsTime: wifiPop.diagDnsTime
                diagDownload: wifiPop.diagDownload
                diagUpload: wifiPop.diagUpload
                diagBufferbloat: wifiPop.diagBufferbloat
                diagBufferbloatOk: wifiPop.diagBufferbloatOk
                diagWifiStandard: wifiPop.diagWifiStandard
                histSignal: wifiPop.histSignal
                histNoise: wifiPop.histNoise
                histGwPing: wifiPop.histGwPing
                histGwJitter: wifiPop.histGwJitter
                histGwLoss: wifiPop.histGwLoss
                histNetPing: wifiPop.histNetPing
                histNetJitter: wifiPop.histNetJitter
                histNetLoss: wifiPop.histNetLoss
                histDnsTime: wifiPop.histDnsTime
                onSpeedTestRequested: { wifiPop.diagDownload = ""; wifiPop.diagUpload = ""; wifiPop.diagBufferbloat = ""; wifiPop.speedTestRunning = true; speedTestProc.running = true; }
                onChannelScanRequested: wifiPop.startChannelScan()
                onDnsChanged: (server) => wifiPop.switchDns(server)
                onExportRequested: wifiPop.exportReport()
                onRerunRequested: wifiPop.startDiagnostics()
            }

            Item {
                id: channelSection
                Layout.fillWidth: true
                implicitHeight: Math.max(channelView.implicitHeight, channelSkeleton.implicitHeight)
                Layout.preferredHeight: implicitHeight
                visible: wifiPop.popupState === "channels"
                opacity: wifiPop.popupState === "channels" ? 1 : 0
                clip: true
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }

                WifiChannels {
                    id: channelView
                    anchors.fill: parent
                    opacity: wifiPop.channelLoading ? 0 : 1
                    enabled: opacity > 0.01
                    Behavior on opacity {
                        Components.Anim {
                            duration: Theme.animContentSwap
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    channelModel: channelModel
                    currentChannel: wifiPop.currentChannel
                    currentBand: wifiPop.currentBand
                    scanning: channelScanProc.running
                }

                ColumnLayout {
                    id: channelSkeleton
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: 8
                    opacity: wifiPop.channelLoading ? 1 : 0
                    visible: opacity > 0
                    z: 1
                    Behavior on opacity {
                        Components.Anim {
                            duration: Theme.animContentSwap
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                    Column {
                        Layout.fillWidth: true
                        spacing: 0

                        Repeater {
                            model: ListModel {
                                ListElement { skelWidth: 120 }
                                ListElement { skelWidth: 150 }
                                ListElement { skelWidth: 100 }
                                ListElement { skelWidth: 140 }
                                ListElement { skelWidth: 110 }
                            }
                            delegate: Item {
                                required property int skelWidth
                                required property int index
                                width: parent.width
                                height: 52

                                ColumnLayout {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 6

                                    RowLayout {
                                        spacing: 6
                                        Rectangle { width: 36; height: 10; radius: 5; color: Theme.bg3 }
                                        Rectangle { width: 40; height: 10; radius: 5; color: Theme.bg3 }
                                        Item { Layout.fillWidth: true }
                                        Rectangle { width: 65; height: 10; radius: 5; color: Theme.bg3 }
                                    }
                                    Rectangle { width: skelWidth; height: 8; radius: 4; color: Theme.bg3 }
                                }

                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    PauseAnimation { duration: index * 120 }
                                    Components.Anim { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                    Components.Anim { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                                }
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
