import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: details
    Layout.fillWidth: true; spacing: 8

    property bool active: false

    // ── Live metrics ──────────────────────────────────────────
    property string dSsid: ""
    property int    dFreq: 0
    property real   dSignal: 0
    property real   dNoise: -95
    property real   dLinkRate: 0
    property string dGateway: ""
    property string dDns: ""
    property real   dRouterPing: 0
    property real   dInternetPing: 0
    property real   dDnsLookup: 0

    // ── Sparkline histories (last 30 samples) ─────────────────
    property var histLinkRate: []
    property var histSignal: []
    property var histNoise: []
    property var histRouterPing: []
    property var histInternetPing: []
    property var histDnsLookup: []

    // ── Loss / jitter tracking ────────────────────────────────
    property var routerPingLog: []
    property var internetPingLog: []
    property real dRouterJitter: 0
    property real dInternetJitter: 0
    property int  dRouterLoss: 0
    property int  dInternetLoss: 0

    // ── Speed test state ──────────────────────────────────────
    property string speedState: "idle"   // idle | running | done
    property real speedDown: 0
    property real speedUp: 0
    property string speedMsg: ""

    // ── Signal message dismiss ────────────────────────────────
    property bool sigMsgDismissed: false

    // ── Helpers ───────────────────────────────────────────────
    readonly property int maxHist: 30
    readonly property int labelWidth: 70
    readonly property int valueWidth: 80

    function pushHist(arr, val) {
        var a = arr.slice();
        a.push(val);
        if (a.length > maxHist) a.shift();
        return a;
    }

    function calcJitter(hist) {
        if (hist.length < 2) return 0;
        var sum = 0;
        for (var i = 1; i < hist.length; i++)
            sum += Math.abs(hist[i] - hist[i - 1]);
        return sum / (hist.length - 1);
    }

    function calcLoss(log) {
        if (log.length === 0) return 0;
        var f = 0;
        for (var i = 0; i < log.length; i++) if (!log[i]) f++;
        return Math.round(f / log.length * 100);
    }

    function freqBand(f) {
        if (f >= 5925) return "6 GHz";
        if (f >= 4900) return "5 GHz";
        if (f > 0)     return "2.4 GHz";
        return "";
    }

    function signalColor(s) {
        if (s >= -60) return Theme.greenBright;
        if (s >= -75) return Theme.orangeBright;
        return Theme.redBright;
    }

    function signalMsg(s) {
        if (s >= -60) return "";
        if (s >= -75) return "Between -60 and -75 dBm — functional but not ideal. Drywall costs ~3–6 dB per wall, concrete/brick ~10–15 dB. Moving closer or adjusting AP antenna orientation can help.";
        return "Weak signal below -75 dBm — connection may be unreliable. Try moving significantly closer to the access point.";
    }

    function pingColor(ms) {
        if (ms <= 0) return Theme.fg4;
        if (ms < 20) return Theme.greenBright;
        if (ms < 50) return Theme.orangeBright;
        return Theme.redBright;
    }

    function jitterColor(ms) {
        if (ms < 5)  return Theme.greenBright;
        if (ms < 20) return Theme.orangeBright;
        return Theme.redBright;
    }

    function lossColor(pct) {
        if (pct === 0) return Theme.greenBright;
        if (pct <= 3)  return Theme.yellowBright;
        return Theme.redBright;
    }

    function resetAll() {
        dSsid = ""; dFreq = 0; dSignal = 0; dNoise = -95; dLinkRate = 0;
        dGateway = ""; dDns = ""; dRouterPing = 0; dInternetPing = 0; dDnsLookup = 0;
        histLinkRate = []; histSignal = []; histNoise = [];
        histRouterPing = []; histInternetPing = []; histDnsLookup = [];
        routerPingLog = []; internetPingLog = [];
        dRouterJitter = 0; dInternetJitter = 0; dRouterLoss = 0; dInternetLoss = 0;
        speedState = "idle"; speedDown = 0; speedUp = 0; speedMsg = "";
        sigMsgDismissed = false;
    }

    onActiveChanged: {
        if (active) { resetAll(); pollTimer.running = true; pollProc.running = true; }
        else { pollTimer.running = false; }
    }

    // ── Poll timer ────────────────────────────────────────────
    Timer {
        id: pollTimer; interval: 3000; repeat: true; running: false
        onTriggered: { if (!pollProc.running) pollProc.running = true; }
    }

    // ── Poll process ──────────────────────────────────────────
    Process {
        id: pollProc; running: false
        command: ["bash", "-c",
            "iface=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1); " +
            "[ -z \"$iface\" ] && echo END && exit 0; " +

            "link=$(iw dev \"$iface\" link 2>/dev/null); " +
            "echo \"$link\" | awk '" +
                "/SSID:/ { sub(/.*SSID: /, \"\"); print \"ssid=\" $0 } " +
                "/freq:/ { print \"freq=\" $2 } " +
                "/signal:/ { print \"signal=\" $2 } " +
                "/tx bitrate:/ { print \"linkrate=\" $3 } " +
            "'; " +

            "noise=$(iw dev \"$iface\" survey dump 2>/dev/null | awk '/noise:/ { print $2; exit }'); " +
            "echo \"noise=${noise:--95}\"; " +

            "gw=$(ip route | awk '/default/ {print $3; exit}'); " +
            "echo \"gateway=$gw\"; " +
            "dns=$(grep -m1 nameserver /etc/resolv.conf | awk '{print $2}'); " +
            "echo \"dns=$dns\"; " +

            "if [ -n \"$gw\" ]; then " +
                "rp=$(ping -c 1 -W 1 \"$gw\" 2>/dev/null | awk -F'[= ]' '/time=/{for(i=1;i<=NF;i++) if($i==\"time\") print $(i+1)}'); " +
                "echo \"rping=${rp:-timeout}\"; " +
            "else echo rping=timeout; fi; " +

            "ip_res=$(ping -c 1 -W 1 1.1.1.1 2>/dev/null | awk -F'[= ]' '/time=/{for(i=1;i<=NF;i++) if($i==\"time\") print $(i+1)}'); " +
            "echo \"iping=${ip_res:-timeout}\"; " +

            "if [ -n \"$dns\" ]; then " +
                "dl=$(timeout 2 dig @\"$dns\" google.com +stats 2>/dev/null | awk '/Query time:/ { print $4 }'); " +
                "echo \"dlookup=${dl:-timeout}\"; " +
            "else echo dlookup=timeout; fi; " +

            "echo END"
        ]
        stdout: SplitParser {
            onRead: (line) => {
                if (line === "END") return;
                var eq = line.indexOf("=");
                if (eq < 0) return;
                var key = line.substring(0, eq);
                var val = line.substring(eq + 1);

                if (key === "ssid")     details.dSsid = val;
                else if (key === "freq")     details.dFreq = parseInt(val) || 0;
                else if (key === "signal") {
                    var s = parseFloat(val) || 0;
                    details.dSignal = s;
                    details.histSignal = details.pushHist(details.histSignal, s);
                }
                else if (key === "noise") {
                    var n = parseFloat(val) || -95;
                    details.dNoise = n;
                    details.histNoise = details.pushHist(details.histNoise, n);
                }
                else if (key === "linkrate") {
                    var lr = parseFloat(val) || 0;
                    details.dLinkRate = lr;
                    details.histLinkRate = details.pushHist(details.histLinkRate, lr);
                }
                else if (key === "gateway")  details.dGateway = val;
                else if (key === "dns")      details.dDns = val;
                else if (key === "rping") {
                    if (val === "timeout") {
                        details.routerPingLog = details.pushHist(details.routerPingLog, false);
                    } else {
                        var rp = parseFloat(val) || 0;
                        details.dRouterPing = rp;
                        details.histRouterPing = details.pushHist(details.histRouterPing, rp);
                        details.routerPingLog = details.pushHist(details.routerPingLog, true);
                    }
                    details.dRouterJitter = details.calcJitter(details.histRouterPing);
                    details.dRouterLoss = details.calcLoss(details.routerPingLog);
                }
                else if (key === "iping") {
                    if (val === "timeout") {
                        details.internetPingLog = details.pushHist(details.internetPingLog, false);
                    } else {
                        var ipv = parseFloat(val) || 0;
                        details.dInternetPing = ipv;
                        details.histInternetPing = details.pushHist(details.histInternetPing, ipv);
                        details.internetPingLog = details.pushHist(details.internetPingLog, true);
                    }
                    details.dInternetJitter = details.calcJitter(details.histInternetPing);
                    details.dInternetLoss = details.calcLoss(details.internetPingLog);
                }
                else if (key === "dlookup") {
                    if (val !== "timeout") {
                        var dl = parseFloat(val) || 0;
                        details.dDnsLookup = dl;
                        details.histDnsLookup = details.pushHist(details.histDnsLookup, dl);
                    }
                }
            }
        }
    }

    // ── Speed test process ────────────────────────────────────
    Process {
        id: speedProc; running: false
        command: ["bash", "-c",
            "dl=$(curl -o /dev/null -s -w '%{speed_download}' --max-time 10 " +
                "'https://speed.cloudflare.com/__down?bytes=10000000' 2>/dev/null); " +
            "dl_mbps=$(awk \"BEGIN {printf \\\"%.1f\\\", $dl * 8 / 1000000}\"); " +
            "echo \"down=$dl_mbps\"; " +

            "ul=$(dd if=/dev/urandom bs=1M count=5 2>/dev/null | " +
                "curl -X POST -o /dev/null -s -w '%{speed_upload}' --max-time 10 " +
                "--data-binary @- 'https://speed.cloudflare.com/__up' 2>/dev/null); " +
            "ul_mbps=$(awk \"BEGIN {printf \\\"%.1f\\\", $ul * 8 / 1000000}\"); " +
            "echo \"up=$ul_mbps\"; " +

            "gw=$(ip route | awk '/default/ {print $3; exit}'); " +
            "if [ -n \"$gw\" ]; then " +
                "loaded=$(ping -c 3 -W 1 \"$gw\" 2>/dev/null | tail -1 | awk -F'/' '{print $5}'); " +
                "echo \"loadping=${loaded:-0}\"; " +
            "fi; " +

            "echo END"
        ]
        stdout: SplitParser {
            onRead: (line) => {
                if (line === "END") { details.speedState = "done"; return; }
                var eq = line.indexOf("=");
                if (eq < 0) return;
                var key = line.substring(0, eq);
                var val = line.substring(eq + 1);
                if (key === "down") details.speedDown = parseFloat(val) || 0;
                else if (key === "up") details.speedUp = parseFloat(val) || 0;
                else if (key === "loadping") {
                    var lp = parseFloat(val) || 0;
                    var base = details.dRouterPing > 0 ? details.dRouterPing : 1;
                    if (lp > base * 3 && lp > 10) {
                        var ratio = (lp / base).toFixed(1);
                        details.speedMsg = "Lag under load: router ping spiked from " +
                            base.toFixed(0) + "ms to " + lp.toFixed(0) + "ms (" + ratio + "x) " +
                            "while maxing out your connection.";
                    }
                }
            }
        }
        onExited: { if (details.speedState !== "done") details.speedState = "done"; }
    }

    // ═══════════════════════════════════════════════════════════
    // ── UI ────────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════

    Text {
        text: "Figure out why your Wi-Fi is bad and fix it."
        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ── SSID + band badge ─────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Rectangle {
            width: 8; height: 8; radius: 4
            color: details.dSsid !== "" ? Theme.greenBright : Theme.fg4
        }
        Text {
            text: details.dSsid || "Not connected"
            color: Theme.fg; font.family: Theme.fontFamily
            font.pixelSize: Theme.headerFontSize; font.bold: true
            Layout.fillWidth: true; elide: Text.ElideRight
        }
        Rectangle {
            visible: details.dFreq > 0
            width: bandText.implicitWidth + 14; height: 20; radius: Theme.btnRadius
            color: Theme.bg2; border.width: 1; border.color: Theme.bg3
            Text {
                id: bandText; anchors.centerIn: parent
                text: details.freqBand(details.dFreq)
                color: Theme.fg3; font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
            }
        }
    }

    // ── Link Rate ─────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Link Rate"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dLinkRate > 0 ? Math.round(details.dLinkRate) + "  Mbps" : "—"
            color: Theme.orangeBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline { values: details.histLinkRate; lineColor: Theme.orangeBright; Layout.fillWidth: true; implicitHeight: 20 }
    }

    // ── Signal ────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Signal"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dSignal !== 0 ? details.dSignal.toFixed(0) + "  dBm" : "—"
            color: details.signalColor(details.dSignal); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline { values: details.histSignal; lineColor: details.signalColor(details.dSignal); Layout.fillWidth: true; implicitHeight: 20 }
    }

    // ── Signal quality warning ────────────────────────────────
    Rectangle {
        visible: !details.sigMsgDismissed && details.signalMsg(details.dSignal) !== ""
        Layout.fillWidth: true
        Layout.preferredHeight: sigMsgText.implicitHeight + 20
        radius: Theme.btnRadius
        color: Theme.bg2; border.width: 1; border.color: Theme.bg3
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }

        Text {
            id: sigMsgText
            anchors {
                left: parent.left; leftMargin: 10
                right: dismissBtn.left; rightMargin: 6
                top: parent.top; topMargin: 10
            }
            text: details.signalMsg(details.dSignal)
            color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
            wrapMode: Text.WordWrap; lineHeight: 1.2
        }

        Rectangle {
            id: dismissBtn
            anchors { right: parent.right; rightMargin: 6; top: parent.top; topMargin: 6 }
            width: 22; height: 22; radius: Theme.hoverRadius; color: "transparent"
            Rectangle {
                anchors.fill: parent; radius: parent.radius; color: Theme.bg3
                opacity: dismissA.pressed ? 0.9 : (dismissA.containsMouse ? 0.6 : 0)
                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
            }
            scale: dismissA.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
            transformOrigin: Item.Center
            Text {
                anchors.centerIn: parent; text: "×"
                color: dismissA.containsMouse ? Theme.fg : Theme.fg4
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
            MouseArea { id: dismissA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: details.sigMsgDismissed = true }
        }
    }

    // ── Noise ─────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Noise"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dNoise.toFixed(0) + "  dBm"
            color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline { values: details.histNoise; lineColor: Theme.greenBright; Layout.fillWidth: true; implicitHeight: 20 }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ═══════════════════════════════════════════════════════════
    // ── Router ────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════
    Text { text: "Router"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Ping"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dRouterPing > 0 ? details.dRouterPing.toFixed(0) + "  ms" : "—"
            color: details.pingColor(details.dRouterPing); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline { values: details.histRouterPing; lineColor: details.pingColor(details.dRouterPing); Layout.fillWidth: true; implicitHeight: 20 }
    }

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Jitter"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dRouterJitter > 0 ? details.dRouterJitter.toFixed(1) + "  ms" : "—"
            color: details.jitterColor(details.dRouterJitter); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline { values: details.histRouterPing; lineColor: details.jitterColor(details.dRouterJitter); Layout.fillWidth: true; implicitHeight: 20 }
    }

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Loss"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dRouterLoss + "%"
            color: details.lossColor(details.dRouterLoss); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline {
            values: {
                var a = [];
                for (var i = 0; i < details.routerPingLog.length; i++)
                    a.push(details.routerPingLog[i] ? 0 : 1);
                return a;
            }
            lineColor: details.lossColor(details.dRouterLoss); Layout.fillWidth: true; implicitHeight: 20
        }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ═══════════════════════════════════════════════════════════
    // ── Internet ──────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════
    Text { text: "Internet"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
    Text { text: "Connected to 1.1.1.1"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Ping"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dInternetPing > 0 ? details.dInternetPing.toFixed(0) + "  ms" : "—"
            color: details.pingColor(details.dInternetPing); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline { values: details.histInternetPing; lineColor: details.pingColor(details.dInternetPing); Layout.fillWidth: true; implicitHeight: 20 }
    }

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Jitter"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dInternetJitter > 0 ? details.dInternetJitter.toFixed(1) + "  ms" : "—"
            color: details.jitterColor(details.dInternetJitter); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline { values: details.histInternetPing; lineColor: details.jitterColor(details.dInternetJitter); Layout.fillWidth: true; implicitHeight: 20 }
    }

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Loss"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dInternetLoss + "%"
            color: details.lossColor(details.dInternetLoss); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline {
            values: {
                var a = [];
                for (var i = 0; i < details.internetPingLog.length; i++)
                    a.push(details.internetPingLog[i] ? 0 : 1);
                return a;
            }
            lineColor: details.lossColor(details.dInternetLoss); Layout.fillWidth: true; implicitHeight: 20
        }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ═══════════════════════════════════════════════════════════
    // ── DNS ───────────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════
    Text { text: "DNS"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
    Text {
        text: (details.dGateway === details.dDns ? "Router assigned" : "Custom") +
              (details.dDns ? " · " + details.dDns : "")
        color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight; Layout.fillWidth: true
    }

    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: "Lookup"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: details.labelWidth }
        Text {
            text: details.dDnsLookup > 0 ? details.dDnsLookup.toFixed(0) + "  ms" : "—"
            color: details.pingColor(details.dDnsLookup); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: details.valueWidth
        }
        Sparkline { values: details.histDnsLookup; lineColor: details.pingColor(details.dDnsLookup); Layout.fillWidth: true; implicitHeight: 20 }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ═══════════════════════════════════════════════════════════
    // ── Speed Test ────────────────────────────────────────────
    // ═══════════════════════════════════════════════════════════
    Text { text: "Speed Test"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }

    // ── Results ───────────────────────────────────────────────
    RowLayout {
        visible: details.speedState === "done"
        Layout.fillWidth: true; spacing: 16
        ColumnLayout {
            spacing: 2
            Text { text: details.speedDown.toFixed(1); color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
            Text { text: "↓ Mbps"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
        }
        ColumnLayout {
            spacing: 2
            Text { text: details.speedUp.toFixed(1); color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
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
            scale: retestA.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
            transformOrigin: Item.Center
            Text { id: retestLabel; anchors.centerIn: parent; text: "Retest"
                color: retestA.containsMouse ? Theme.blueBright : Theme.fg4
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            MouseArea { id: retestA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: { details.speedState = "running"; details.speedMsg = ""; speedProc.running = true; } }
        }
    }

    // ── Bufferbloat message ───────────────────────────────────
    Text {
        visible: details.speedMsg !== ""
        text: details.speedMsg
        color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
        wrapMode: Text.WordWrap; Layout.fillWidth: true; lineHeight: 1.2
    }

    // ── Run button (idle) ─────────────────────────────────────
    Rectangle {
        visible: details.speedState === "idle"
        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
        color: "transparent"
        Rectangle {
            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
            opacity: speedBtnA.pressed ? 0.9 : (speedBtnA.containsMouse ? 0.6 : 0.3)
            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
        }
        scale: speedBtnA.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
        transformOrigin: Item.Center
        RowLayout {
            anchors.centerIn: parent; spacing: 6
            Text { text: "󰓅"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
            Text { text: "Run Speed Test"; color: speedBtnA.containsMouse ? Theme.fg : Theme.fg3
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        }
        MouseArea { id: speedBtnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
            onClicked: { details.speedState = "running"; speedProc.running = true; } }
    }

    // ── Progress (running) ────────────────────────────────────
    ColumnLayout {
        visible: details.speedState === "running"
        Layout.fillWidth: true; spacing: 4; Layout.alignment: Qt.AlignHCenter
        Text { text: "Testing…"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }
        Rectangle {
            Layout.fillWidth: true; height: 4; radius: 2; color: Theme.bg3
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
}
