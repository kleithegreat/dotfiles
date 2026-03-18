import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PanelWindow {
    id: wifiPop
    property bool active: false; signal close()
    property bool closing: false
    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:wifi"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property string connectedSsid: ""
    ListModel { id: netModel }
    ListModel { id: knownModel }

    property string popupState: "list"   // list | detail | password | enterprise | connecting | diagnostics
    property string targetSsid: ""
    property string targetSecurity: ""
    property int    targetSignal: 0
    property bool   targetIsConnected: false
    property bool   targetIsKnown: false
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

    onActiveChanged: {
        if (active) {
            wifiPanel.opacity = 0; wifiPanel.scale = 0.92;
            wifiOpenAnim.start();
            resetState(); scan(); loadKnown();
        } else if (!closing) {
            closing = true; wifiCloseAnim.start();
        }
    }

    SequentialAnimation {
        id: wifiOpenAnim
        ParallelAnimation {
            NumberAnimation { target: wifiPanel; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: wifiPanel; property: "scale"; to: 1.0; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: wifiCloseAnim
        ParallelAnimation {
            NumberAnimation { target: wifiPanel; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
            NumberAnimation { target: wifiPanel; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { wifiPop.closing = false; } }
    }

    function resetState() {
        popupState = "list"; targetSsid = ""; targetSecurity = ""; targetSignal = 0;
        targetIsConnected = false; targetIsKnown = false; connectError = "";
        detailIp = ""; detailGateway = ""; detailDns = ""; detailFreq = "";
        diagLoading = false; speedTestRunning = false;
    }

    function scan() { netModel.clear(); connectedSsid = ""; scanProc.running = true; }
    function loadKnown() { knownModel.clear(); knownProc.running = true; }

    function isKnown(ssid) {
        for (let i = 0; i < knownModel.count; i++) if (knownModel.get(i).name === ssid) return true;
        return false;
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
            targetSsid = ssid; targetSecurity = security; popupState = "enterprise";
        } else if (isKnown(ssid)) {
            popupState = "connecting"; targetSsid = ssid;
            connectProc.command = ["nmcli", "dev", "wifi", "connect", ssid];
            connectProc.running = true;
        } else if (security !== "") {
            targetSsid = ssid; targetSecurity = security; popupState = "password";
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
            'nmcli connection delete id "$1" 2>/dev/null; ' +
            'nmcli connection add type wifi ifname "$iface" con-name "$1" ssid "$1" ' +
            'wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2 ' +
            '802-1x.identity "$2" 802-1x.password "$3" && ' +
            'nmcli connection up id "$1"',
            "--", targetSsid, identity, password
        ];
        enterpriseProc.running = true;
    }

    function disconnect() {
        // Disconnect the specific connection by name, not the whole interface
        disconnectProc.command = ["nmcli", "con", "down", "id", connectedSsid];
        disconnectProc.running = true;
    }

    function forgetNetwork(ssid) {
        forgetProc.command = ["nmcli", "con", "delete", "id", ssid];
        forgetProc.running = true;
    }

    function openDetail(ssid, security, signal, isActive) {
        targetSsid = ssid; targetSecurity = security; targetSignal = signal;
        targetIsConnected = isActive; targetIsKnown = isKnown(ssid);
        detailIp = ""; detailGateway = ""; detailDns = ""; detailFreq = "";
        connectError = "";
        popupState = "detail";
        if (isActive) {
            detailProc.command = [
                "bash", "-c",
                'echo "IP|$(nmcli -t -f IP4.ADDRESS con show id "$1" 2>/dev/null | head -1 | cut -d: -f2)"; ' +
                'echo "GW|$(nmcli -t -f IP4.GATEWAY con show id "$1" 2>/dev/null | head -1 | cut -d: -f2)"; ' +
                'echo "DNS|$(nmcli -t -f IP4.DNS con show id "$1" 2>/dev/null | head -1 | cut -d: -f2)"; ' +
                'freq=$(nmcli -t -f IN-USE,FREQ dev wifi list 2>/dev/null | grep "^\\*" | head -1 | cut -d: -f2); ' +
                'if [ -n "$freq" ]; then ' +
                '  if [ "$freq" -lt 3000 ] 2>/dev/null; then freq="$freq MHz (2.4 GHz)"; ' +
                '  elif [ "$freq" -lt 6000 ] 2>/dev/null; then freq="$freq MHz (5 GHz)"; ' +
                '  else freq="$freq MHz (6 GHz)"; fi; ' +
                'fi; ' +
                'echo "FREQ|${freq:-}"',
                "--", ssid
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
        id: knownProc; command: ["nmcli", "-t", "-f", "NAME", "con", "show"]; running: false
        stdout: SplitParser { onRead: (line) => { if (line.trim()) knownModel.append({ name: line.trim() }); } }
    }

    Process {
        id: activeProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "con", "show", "--active"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let parts = line.split(":");
            if (parts.length >= 3 && parts[1] === "802-11-wireless") {
                wifiPop.connectedSsid = parts[0];
                for (let i = 0; i < netModel.count; i++) {
                    if (netModel.get(i).ssid === parts[0]) {
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

    // ── Sparkline component ───────────────────────────────────
    Component {
        id: sparklineComponent
        Canvas {
            id: sparkCanvas
            property var dataPoints: []
            property color lineColor: Theme.greenBright
            property real minVal: NaN
            property real maxVal: NaN

            width: 120; height: 20

            onDataPointsChanged: requestPaint()
            onLineColorChanged: requestPaint()

            onPaint: {
                let ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                let pts = dataPoints;
                if (!pts || pts.length < 2) return;

                let lo = isNaN(minVal) ? Math.min(...pts) : minVal;
                let hi = isNaN(maxVal) ? Math.max(...pts) : maxVal;
                if (hi === lo) { hi = lo + 1; }

                let pad = 2;
                let w = width - pad * 2;
                let h = height - pad * 2;

                ctx.beginPath();
                ctx.strokeStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.8);
                ctx.lineWidth = 1.5;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";

                for (let i = 0; i < pts.length; i++) {
                    let x = pad + (i / (pts.length - 1)) * w;
                    let y = pad + h - ((pts[i] - lo) / (hi - lo)) * h;
                    if (i === 0) ctx.moveTo(x, y);
                    else ctx.lineTo(x, y);
                }
                ctx.stroke();
            }
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

    // ── Popup card ────────────────────────────────────────────
    Rectangle {
        id: wifiPanel
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth; height: wifiCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: 0.92
        transformOrigin: Item.TopRight
        Behavior on height { NumberAnimation { duration: Theme.animHeightResize; easing.type: Easing.OutCubic } }
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
                        return "󰖩  Wi-Fi";
                    }
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                // Back button
                Rectangle {
                    visible: wifiPop.popupState === "detail" || wifiPop.popupState === "password" || wifiPop.popupState === "enterprise" || wifiPop.popupState === "diagnostics"
                    width: backLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: backA.pressed ? 0.9 : (backA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: backA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: backLabel; anchors.centerIn: parent; text: "← Back"; color: backA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: backA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.resetState() }
                }
                // Rescan button (list only)
                Rectangle {
                    visible: wifiPop.popupState === "list"
                    width: rescanLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: rescanA.pressed ? 0.9 : (rescanA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: rescanA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: rescanLabel; anchors.centerIn: parent; text: "Rescan"; color: rescanA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: rescanA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.scan() }
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
                    Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ══════════════════════════════════════════════════
            // ── LIST STATE ────────────────────────────────────
            // ══════════════════════════════════════════════════
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: Math.min(220, netCol.implicitHeight > 0 ? netCol.implicitHeight : 220); Layout.maximumHeight: 220
                visible: wifiPop.popupState === "list"
                opacity: wifiPop.popupState === "list" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }

                Flickable {
                    anchors.fill: parent
                    contentHeight: netCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: netCol; width: parent.width; spacing: 2
                        Repeater {
                            model: netModel
                            Rectangle {
                                id: netItem; required property string ssid; required property int signal
                                required property string security; required property bool active
                                required property int index
                                width: netCol.width; height: 34; radius: Theme.hoverRadius
                                color: "transparent"

                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                    opacity: niRowArea.pressed ? 0.9 : (niRowArea.containsMouse ? 0.6 : 0)
                                    Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                                }
                                scale: niRowArea.pressed ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                transformOrigin: Item.Center

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: 4; spacing: 6

                                    // Checkmark for connected, signal-strength icon otherwise
                                    Text {
                                        text: netItem.active ? "󰄬" : wifiPop.signalIcon(netItem.signal)
                                        color: {
                                            if (netItem.active) return Theme.greenBright;
                                            if (netItem.signal > 60) return Theme.fg;
                                            if (netItem.signal > 30) return Theme.fg3;
                                            return Theme.fg4;
                                        }
                                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                                    }
                                    // SSID
                                    Text { text: netItem.ssid; color: netItem.active ? Theme.greenBright : Theme.fg
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                        Layout.fillWidth: true; elide: Text.ElideRight }
                                    // Enterprise badge
                                    Text { visible: wifiPop.isEnterprise(netItem.security); text: "󱄤"; color: Theme.yellowBright
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                    // Lock icon
                                    Text { visible: netItem.security !== "" && !wifiPop.isEnterprise(netItem.security); text: "󰌾"; color: Theme.fg4
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                    // Signal %
                                    Text { text: netItem.signal + "%"; color: Theme.fg4
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                    // ⓘ info button
                                    Rectangle {
                                        width: 24; height: 24; radius: 12
                                        color: "transparent"
                                        Rectangle {
                                            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                            opacity: infoA.pressed ? 0.9 : (infoA.containsMouse ? 0.7 : 0)
                                            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                                        }
                                        Text { anchors.centerIn: parent; text: "󰋼"; color: infoA.containsMouse ? Theme.blueBright : Theme.fg4
                                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                        MouseArea { id: infoA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                            onClicked: wifiPop.openDetail(netItem.ssid, netItem.security, netItem.signal, netItem.active) }
                                    }
                                }

                                // Row click: connected → detail, otherwise → connect
                                MouseArea {
                                    id: niRowArea; anchors.left: parent.left; anchors.top: parent.top
                                    anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.rightMargin: 30
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: {
                                        if (netItem.active)
                                            wifiPop.openDetail(netItem.ssid, netItem.security, netItem.signal, true);
                                        else
                                            wifiPop.connectTo(netItem.ssid, netItem.security);
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Skeleton loading rows ─────────────────────
                Column {
                    visible: netModel.count === 0
                    anchors.fill: parent; anchors.topMargin: 4
                    spacing: 0

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
                            width: parent.width; height: 36
                            RowLayout {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: 6; anchors.rightMargin: 6
                                spacing: 8

                                Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Item { Layout.fillWidth: true }
                                Rectangle { width: 10; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Rectangle { width: 28; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                            }

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 120 }
                                NumberAnimation { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            // ══════════════════════════════════════════════════
            // ── DETAIL STATE (iOS-style info page) ────────────
            // ══════════════════════════════════════════════════
            ColumnLayout {
                visible: wifiPop.popupState === "detail"
                opacity: wifiPop.popupState === "detail" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                Layout.fillWidth: true; spacing: 10

                // Status row
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    Text { text: wifiPop.signalIcon(wifiPop.targetSignal); color: wifiPop.targetIsConnected ? Theme.greenBright : Theme.fg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize + 4 }
                    ColumnLayout {
                        spacing: 2; Layout.fillWidth: true
                        Text { text: wifiPop.targetIsConnected ? "Connected" : (wifiPop.targetIsKnown ? "Known Network" : "Not Connected")
                            color: wifiPop.targetIsConnected ? Theme.greenBright : Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                        Text { text: wifiPop.targetSecurity || "Open"; color: Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                    }
                    Text { text: wifiPop.targetSignal + "%"; color: Theme.fg4
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }

                // Detail fields (connected only)
                Rectangle {
                    visible: wifiPop.targetIsConnected
                        Layout.fillWidth: true; height: detailGrid.implicitHeight + 16; radius: Theme.btnRadius; color: Theme.bg2

                    GridLayout {
                        id: detailGrid; anchors.fill: parent; anchors.margins: 8
                        columns: 2; columnSpacing: 12; rowSpacing: 6

                        Text { text: "IP Address"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                        Text { text: wifiPop.detailIp || "…"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                            Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

                        Text { text: "Gateway"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                        Text { text: wifiPop.detailGateway || "…"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                            Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

                        Text { text: "DNS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                        Text { text: wifiPop.detailDns || "…"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                            Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

                        Text { visible: wifiPop.detailFreq !== ""; text: "Frequency"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                        Text { visible: wifiPop.detailFreq !== ""; text: wifiPop.detailFreq; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                            Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }
                    }
                }

                // Action buttons
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 6

                    // Connect button (not connected)
                    Rectangle {
                        visible: !wifiPop.targetIsConnected
                        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
                        color: detailConnA.containsMouse ? Theme.blueBright : Theme.bg3
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        scale: detailConnA.pressed ? 0.98 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                        transformOrigin: Item.Center
                        Text { anchors.centerIn: parent; text: "Connect"; color: detailConnA.containsMouse ? Theme.bg : Theme.fg
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                        MouseArea { id: detailConnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: wifiPop.connectTo(wifiPop.targetSsid, wifiPop.targetSecurity) }
                    }

                    // Disconnect button (connected only)
                    Rectangle {
                        visible: wifiPop.targetIsConnected
                        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                            opacity: detailDcA.pressed ? 0.9 : (detailDcA.containsMouse ? 0.6 : 0)
                            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                        }
                        scale: detailDcA.pressed ? 0.98 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                        transformOrigin: Item.Center
                        Text { anchors.centerIn: parent; text: "Disconnect"; color: detailDcA.containsMouse ? Theme.fg : Theme.fg4
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        MouseArea { id: detailDcA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: wifiPop.disconnect() }
                    }

                    // Forget button (known networks only)
                    Rectangle {
                        visible: wifiPop.targetIsKnown
                        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                            opacity: forgetA.pressed ? 0.9 : (forgetA.containsMouse ? 0.6 : 0)
                            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                        }
                        scale: forgetA.pressed ? 0.98 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                        transformOrigin: Item.Center
                        Text { anchors.centerIn: parent; text: "Forget This Network"; color: forgetA.containsMouse ? Theme.redBright : Theme.fg4
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        MouseArea { id: forgetA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: wifiPop.forgetNetwork(wifiPop.targetSsid) }
                    }

                    // Diagnostics button (connected only)
                    Rectangle {
                        visible: wifiPop.targetIsConnected
                        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
                        color: "transparent"
                        Rectangle {
                            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                            opacity: detailDiagA.pressed ? 0.9 : (detailDiagA.containsMouse ? 0.6 : 0.3)
                            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                        }
                        scale: detailDiagA.pressed ? 0.98 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                        transformOrigin: Item.Center
                        Text { anchors.centerIn: parent; text: "󱍸  Run Diagnostics"; color: detailDiagA.containsMouse ? Theme.blueBright : Theme.fg4
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        MouseArea { id: detailDiagA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: wifiPop.startDiagnostics() }
                    }
                }
            }

            // ══════════════════════════════════════════════════
            // ── PASSWORD STATE ────────────────────────────────
            // ══════════════════════════════════════════════════
            ColumnLayout {
                visible: wifiPop.popupState === "password"
                opacity: wifiPop.popupState === "password" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                Layout.fillWidth: true; spacing: 8

                Text { text: "Network: " + wifiPop.targetSsid; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
                    border.width: 1; border.color: pskInput.activeFocus ? Theme.blueBright : Theme.bg3
                    Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
                    TextInput {
                        id: pskInput; anchors.fill: parent; anchors.margins: 8
                        color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        echoMode: TextInput.Password; clip: true
                        Keys.onReturnPressed: wifiPop.submitPassword(text)
                        Keys.onEscapePressed: wifiPop.resetState()
                    }
                    Text { visible: !pskInput.text; text: "Password"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: Theme.btnRadius
                    color: connPskA.containsMouse ? Theme.blueBright : Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    scale: connPskA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { anchors.centerIn: parent; text: "Connect"; color: connPskA.containsMouse ? Theme.bg : Theme.fg
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    MouseArea { id: connPskA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.submitPassword(pskInput.text) }
                }
            }

            Connections {
                target: wifiPop
                function onPopupStateChanged() {
                    if (wifiPop.popupState === "password") { pskInput.text = ""; pskInput.forceActiveFocus(); }
                    if (wifiPop.popupState === "enterprise") { eapIdentity.text = ""; eapPassword.text = ""; eapIdentity.forceActiveFocus(); }
                }
            }

            // ══════════════════════════════════════════════════
            // ── ENTERPRISE STATE ──────────────────────────────
            // ══════════════════════════════════════════════════
            ColumnLayout {
                visible: wifiPop.popupState === "enterprise"
                opacity: wifiPop.popupState === "enterprise" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                Layout.fillWidth: true; spacing: 8

                Text { text: "Network: " + wifiPop.targetSsid; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                Text { text: "802.1X · PEAP / MSCHAPv2"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }

                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
                    border.width: 1; border.color: eapIdentity.activeFocus ? Theme.blueBright : Theme.bg3
                    Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
                    TextInput {
                        id: eapIdentity; anchors.fill: parent; anchors.margins: 8
                        color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; clip: true
                        Keys.onReturnPressed: eapPassword.forceActiveFocus()
                        Keys.onEscapePressed: wifiPop.resetState()
                    }
                    Text { visible: !eapIdentity.text; text: "Username / Identity"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
                    border.width: 1; border.color: eapPassword.activeFocus ? Theme.blueBright : Theme.bg3
                    Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
                    TextInput {
                        id: eapPassword; anchors.fill: parent; anchors.margins: 8
                        color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        echoMode: TextInput.Password; clip: true
                        Keys.onReturnPressed: wifiPop.submitEnterprise(eapIdentity.text, text)
                        Keys.onEscapePressed: wifiPop.resetState()
                    }
                    Text { visible: !eapPassword.text; text: "Password"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 30; radius: Theme.btnRadius
                    color: connEapA.containsMouse ? Theme.blueBright : Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    scale: connEapA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { anchors.centerIn: parent; text: "Sign In"; color: connEapA.containsMouse ? Theme.bg : Theme.fg
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    MouseArea { id: connEapA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: wifiPop.submitEnterprise(eapIdentity.text, eapPassword.text) }
                }

                Text { text: "Only PEAP/MSCHAPv2 is supported."; color: Theme.fg4; wrapMode: Text.WordWrap
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 2; Layout.fillWidth: true }
            }

            // ══════════════════════════════════════════════════
            // ── CONNECTING STATE ──────────────────────────────
            // ══════════════════════════════════════════════════
            ColumnLayout {
                visible: wifiPop.popupState === "connecting"
                opacity: wifiPop.popupState === "connecting" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                Layout.fillWidth: true; spacing: 8; Layout.alignment: Qt.AlignHCenter

                Text { text: "Connecting to " + wifiPop.targetSsid + "…"; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter; width: 120; height: 4; radius: 2; color: Theme.bg3
                    Rectangle {
                        height: parent.height; radius: parent.radius; color: Theme.blueBright
                        SequentialAnimation on width {
                            loops: Animation.Infinite
                            NumberAnimation { from: 0; to: 120; duration: 1200; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 120; to: 0; duration: 1200; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }

            // ══════════════════════════════════════════════════
            // ── DIAGNOSTICS STATE ─────────────────────────────
            // ══════════════════════════════════════════════════
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 500; Layout.maximumHeight: 500
                visible: wifiPop.popupState === "diagnostics"
                opacity: wifiPop.popupState === "diagnostics" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }

                // ── Skeleton loading ────────────────────────
                Column {
                    visible: wifiPop.diagLoading
                    anchors.fill: parent; anchors.topMargin: 4
                    spacing: 0

                    Repeater {
                        model: ListModel {
                            ListElement { skelWidth: 80 }
                            ListElement { skelWidth: 140 }
                            ListElement { skelWidth: 100 }
                            ListElement { skelWidth: 120 }
                            ListElement { skelWidth: 90 }
                            ListElement { skelWidth: 130 }
                        }
                        delegate: Item {
                            required property int skelWidth
                            required property int index
                            width: parent.width; height: 36
                            RowLayout {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left; anchors.right: parent.right
                                anchors.leftMargin: 6; anchors.rightMargin: 6
                                spacing: 8

                                Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Item { Layout.fillWidth: true }
                                Rectangle { width: 50; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                            }

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 120 }
                                NumberAnimation { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                NumberAnimation { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }

                // ── Diagnostics results ─────────────────────
                Flickable {
                    visible: !wifiPop.diagLoading
                    anchors.fill: parent
                    contentHeight: diagCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: diagCol; width: parent.width; spacing: 6

                        // ── Network header ──────────────────
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: wifiPop.connectedSsid; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                            Rectangle {
                                visible: wifiPop.diagBand !== "" && wifiPop.diagBand !== "unknown"
                                width: bandLabel.implicitWidth + 10; height: 18; radius: 4; color: Theme.bg3
                                Text { id: bandLabel; anchors.centerIn: parent; text: wifiPop.diagBand; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 2 }
                            }
                        }
                        // Wi-Fi standard
                        Text {
                            visible: wifiPop.diagWifiStandard !== "" && wifiPop.diagWifiStandard !== "unknown"
                            text: wifiPop.diagWifiStandard
                            color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                        }
                        // Upgrade warning for old standards
                        Rectangle {
                            visible: wifiPop.diagWifiStandard.indexOf("Wi-Fi 4") >= 0 || wifiPop.diagWifiStandard.indexOf("802.11g") >= 0
                            Layout.fillWidth: true; height: stdWarnText.implicitHeight + 8; radius: Theme.btnRadius
                            color: Theme.bg2; border.width: 1; border.color: Theme.yellowBright
                            Text {
                                id: stdWarnText
                                anchors.centerIn: parent; width: parent.width - 12
                                text: wifiPop.diagBand === "2.4 GHz"
                                    ? "Using an older Wi-Fi standard \u2014 try connecting to a 5 GHz network for better speeds."
                                    : "Using an older Wi-Fi standard. Your router may need a firmware update."
                                color: Theme.yellowBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                                wrapMode: Text.WordWrap
                            }
                        }

                        // ── Link Rate ───────────────────────
                        RowLayout { Layout.fillWidth: true
                            Text { text: "Link Rate"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 50; Layout.fillWidth: true }
                            Text { text: (wifiPop.diagLinkRate && wifiPop.diagLinkRate !== "--") ? wifiPop.diagLinkRate + " Mbps" : "--"
                                color: (wifiPop.diagLinkRate && wifiPop.diagLinkRate !== "--") ? Theme.greenBright : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }

                        // ── Signal ──────────────────────────
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Signal"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Layout.preferredWidth: 50 }
                            Loader {
                                Layout.fillWidth: true; Layout.preferredHeight: 20
                                active: wifiPop.histSignal.length >= 2
                                sourceComponent: sparklineComponent
                                onLoaded: {
                                    item.dataPoints = Qt.binding(function() { return wifiPop.histSignal; });
                                    item.lineColor = Qt.binding(function() { return wifiPop.signalColor(wifiPop.diagSignal); });
                                    item.minVal = -90;
                                    item.maxVal = -30;
                                }
                            }
                            Item { visible: wifiPop.histSignal.length < 2; Layout.fillWidth: true }
                            Text {
                                text: (wifiPop.diagSignal && wifiPop.diagSignal !== "--") ? wifiPop.diagSignal + " dBm" : "--"
                                color: (wifiPop.diagSignal && wifiPop.diagSignal !== "--") ? wifiPop.signalColor(wifiPop.diagSignal) : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight
                            }
                        }
                        Text {
                            visible: {
                                let v = parseInt(wifiPop.diagSignal);
                                return !isNaN(v) && v < -50;
                            }
                            text: {
                                let v = parseInt(wifiPop.diagSignal);
                                if (v >= -60) return "Decent signal. Moving closer to your router could improve speeds.";
                                if (v >= -70) return "Weak signal — functional but not ideal. Try moving closer or adjusting router placement.";
                                return "Very weak signal. Walls and distance are significantly degrading your connection.";
                            }
                            color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                            opacity: 0.8
                        }

                        // ── Noise ───────────────────────────
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Noise"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Layout.preferredWidth: 50 }
                            Loader {
                                Layout.fillWidth: true; Layout.preferredHeight: 20
                                active: wifiPop.histNoise.length >= 2
                                sourceComponent: sparklineComponent
                                onLoaded: {
                                    item.dataPoints = Qt.binding(function() { return wifiPop.histNoise; });
                                    item.lineColor = Theme.greenBright;
                                    item.minVal = -100;
                                    item.maxVal = -60;
                                }
                            }
                            Item { visible: wifiPop.histNoise.length < 2; Layout.fillWidth: true }
                            Text {
                                text: (wifiPop.diagNoise && wifiPop.diagNoise !== "--") ? wifiPop.diagNoise + " dBm" : "--"
                                color: (wifiPop.diagNoise && wifiPop.diagNoise !== "--") ? Theme.greenBright : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight
                            }
                        }

                        // ── Router section ──────────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 4 }
                        Text { text: "󰑩  Router" + (wifiPop.diagGateway && wifiPop.diagGateway !== "--" ? " · " + wifiPop.diagGateway : ""); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Ping"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 50 }
                            Loader { Layout.fillWidth: true; Layout.preferredHeight: 20; active: wifiPop.histGwPing.length >= 2; sourceComponent: sparklineComponent
                                onLoaded: { item.dataPoints = Qt.binding(function() { return wifiPop.histGwPing; }); item.lineColor = Qt.binding(function() { return wifiPop.pingColor(wifiPop.diagGwPing); }); } }
                            Item { visible: wifiPop.histGwPing.length < 2; Layout.fillWidth: true }
                            Text { text: (wifiPop.diagGwPing && wifiPop.diagGwPing !== "--") ? wifiPop.diagGwPing + " ms" : "--"
                                color: (wifiPop.diagGwPing && wifiPop.diagGwPing !== "--") ? wifiPop.pingColor(wifiPop.diagGwPing) : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Jitter"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 50 }
                            Loader { Layout.fillWidth: true; Layout.preferredHeight: 20; active: wifiPop.histGwJitter.length >= 2; sourceComponent: sparklineComponent
                                onLoaded: { item.dataPoints = Qt.binding(function() { return wifiPop.histGwJitter; }); item.lineColor = Qt.binding(function() { return wifiPop.pingColor(wifiPop.diagGwJitter); }); } }
                            Item { visible: wifiPop.histGwJitter.length < 2; Layout.fillWidth: true }
                            Text { text: (wifiPop.diagGwJitter && wifiPop.diagGwJitter !== "--") ? wifiPop.diagGwJitter + " ms" : "--"
                                color: (wifiPop.diagGwJitter && wifiPop.diagGwJitter !== "--") ? wifiPop.pingColor(wifiPop.diagGwJitter) : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Loss"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 50 }
                            Loader { Layout.fillWidth: true; Layout.preferredHeight: 20; active: wifiPop.histGwLoss.length >= 2; sourceComponent: sparklineComponent
                                onLoaded: { item.dataPoints = Qt.binding(function() { return wifiPop.histGwLoss; }); item.lineColor = Qt.binding(function() { return wifiPop.lossColor(wifiPop.diagGwLoss); }); } }
                            Item { visible: wifiPop.histGwLoss.length < 2; Layout.fillWidth: true }
                            Text { text: (wifiPop.diagGwLoss && wifiPop.diagGwLoss !== "--") ? wifiPop.diagGwLoss + "%" : "--"
                                color: (wifiPop.diagGwLoss && wifiPop.diagGwLoss !== "--") ? wifiPop.lossColor(wifiPop.diagGwLoss) : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }

                        // ── Internet section ────────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 4 }
                        Text { text: "󰖩  Internet · 1.1.1.1"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Ping"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 50 }
                            Loader { Layout.fillWidth: true; Layout.preferredHeight: 20; active: wifiPop.histNetPing.length >= 2; sourceComponent: sparklineComponent
                                onLoaded: { item.dataPoints = Qt.binding(function() { return wifiPop.histNetPing; }); item.lineColor = Qt.binding(function() { return wifiPop.pingColor(wifiPop.diagNetPing); }); } }
                            Item { visible: wifiPop.histNetPing.length < 2; Layout.fillWidth: true }
                            Text { text: (wifiPop.diagNetPing && wifiPop.diagNetPing !== "--") ? wifiPop.diagNetPing + " ms" : "--"
                                color: (wifiPop.diagNetPing && wifiPop.diagNetPing !== "--") ? wifiPop.pingColor(wifiPop.diagNetPing) : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Jitter"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 50 }
                            Loader { Layout.fillWidth: true; Layout.preferredHeight: 20; active: wifiPop.histNetJitter.length >= 2; sourceComponent: sparklineComponent
                                onLoaded: { item.dataPoints = Qt.binding(function() { return wifiPop.histNetJitter; }); item.lineColor = Qt.binding(function() { return wifiPop.pingColor(wifiPop.diagNetJitter); }); } }
                            Item { visible: wifiPop.histNetJitter.length < 2; Layout.fillWidth: true }
                            Text { text: (wifiPop.diagNetJitter && wifiPop.diagNetJitter !== "--") ? wifiPop.diagNetJitter + " ms" : "--"
                                color: (wifiPop.diagNetJitter && wifiPop.diagNetJitter !== "--") ? wifiPop.pingColor(wifiPop.diagNetJitter) : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Loss"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 50 }
                            Loader { Layout.fillWidth: true; Layout.preferredHeight: 20; active: wifiPop.histNetLoss.length >= 2; sourceComponent: sparklineComponent
                                onLoaded: { item.dataPoints = Qt.binding(function() { return wifiPop.histNetLoss; }); item.lineColor = Qt.binding(function() { return wifiPop.lossColor(wifiPop.diagNetLoss); }); } }
                            Item { visible: wifiPop.histNetLoss.length < 2; Layout.fillWidth: true }
                            Text { text: (wifiPop.diagNetLoss && wifiPop.diagNetLoss !== "--") ? wifiPop.diagNetLoss + "%" : "--"
                                color: (wifiPop.diagNetLoss && wifiPop.diagNetLoss !== "--") ? wifiPop.lossColor(wifiPop.diagNetLoss) : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }

                        // ── DNS section ─────────────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 4 }
                        Text { text: "󰇖  DNS" + (wifiPop.diagDnsServer && wifiPop.diagDnsServer !== "--" ? " · " + wifiPop.diagDnsServer : ""); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                        RowLayout { Layout.fillWidth: true; spacing: 6
                            Text { text: "Lookup"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 50 }
                            Loader { Layout.fillWidth: true; Layout.preferredHeight: 20; active: wifiPop.histDnsTime.length >= 2; sourceComponent: sparklineComponent
                                onLoaded: { item.dataPoints = Qt.binding(function() { return wifiPop.histDnsTime; }); item.lineColor = Qt.binding(function() { return wifiPop.pingColor(wifiPop.diagDnsTime); }); } }
                            Item { visible: wifiPop.histDnsTime.length < 2; Layout.fillWidth: true }
                            Text { text: (wifiPop.diagDnsTime && wifiPop.diagDnsTime !== "--") ? wifiPop.diagDnsTime + " ms" : "--"
                                color: (wifiPop.diagDnsTime && wifiPop.diagDnsTime !== "--") ? wifiPop.pingColor(wifiPop.diagDnsTime) : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 65; horizontalAlignment: Text.AlignRight }
                        }

                        // ── Speed Test section ──────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 4 }
                        Text { text: "󰓅  Speed Test"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                        RowLayout {
                            visible: wifiPop.diagDownload !== "" && !wifiPop.speedTestRunning
                            Layout.fillWidth: true; spacing: 12
                            ColumnLayout { spacing: 2
                                Text { text: wifiPop.diagDownload || "--"; color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
                                Text { text: "↓ Mbps"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                            }
                            ColumnLayout { spacing: 2
                                Text { text: wifiPop.diagUpload || "--"; color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
                                Text { text: "↑ Mbps"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                            }
                            Item { Layout.fillWidth: true }
                            Rectangle {
                                width: retestLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                                color: "transparent"
                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                    opacity: retestA.pressed ? 0.9 : (retestA.containsMouse ? 0.6 : 0)
                                    Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                                }
                                Text { id: retestLabel; anchors.centerIn: parent; text: "Retest"; color: retestA.containsMouse ? Theme.blueBright : Theme.fg4
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } } }
                                MouseArea { id: retestA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: { wifiPop.diagDownload = ""; wifiPop.diagUpload = ""; wifiPop.diagBufferbloat = ""; wifiPop.speedTestRunning = true; speedTestProc.running = true; } }
                            }
                        }
                        // Bufferbloat result
                        RowLayout {
                            visible: wifiPop.diagBufferbloat !== "" && !wifiPop.speedTestRunning
                            Layout.fillWidth: true; spacing: 6
                            Rectangle {
                                width: 8; height: 8; radius: 4
                                color: wifiPop.diagBufferbloatOk ? Theme.greenBright : Theme.redBright
                            }
                            Text {
                                text: wifiPop.diagBufferbloat
                                color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                                wrapMode: Text.WordWrap; Layout.fillWidth: true
                            }
                        }

                        Rectangle {
                            visible: wifiPop.diagDownload === "" || wifiPop.speedTestRunning
                            Layout.fillWidth: true; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: "transparent"
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                opacity: speedBtnA.pressed ? 0.9 : (speedBtnA.containsMouse ? 0.6 : 0.3)
                                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                id: speedBtnText; anchors.centerIn: parent
                                text: wifiPop.speedTestRunning ? "Testing…" : "Run Speed Test"
                                color: speedBtnA.containsMouse ? Theme.blueBright : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                SequentialAnimation on opacity {
                                    running: wifiPop.speedTestRunning; loops: Animation.Infinite
                                    NumberAnimation { from: 1; to: 0.4; duration: 600 }
                                    NumberAnimation { from: 0.4; to: 1; duration: 600 }
                                }
                            }
                            MouseArea { id: speedBtnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; enabled: !wifiPop.speedTestRunning
                                onClicked: { wifiPop.speedTestRunning = true; speedTestProc.running = true; } }
                        }

                        // ── Rerun diagnostics ───────────────
                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }
                        Rectangle {
                            Layout.fillWidth: true; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: "transparent"
                            Rectangle {
                                anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                opacity: rerunA.pressed ? 0.9 : (rerunA.containsMouse ? 0.6 : 0)
                                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                            }
                            Text { anchors.centerIn: parent; text: "↻ Rerun"; color: rerunA.containsMouse ? Theme.blueBright : Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Behavior on color { ColorAnimation { duration: Theme.animHover } } }
                            MouseArea { id: rerunA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: wifiPop.startDiagnostics() }
                        }
                    }
                }
            }
        }
    }
}