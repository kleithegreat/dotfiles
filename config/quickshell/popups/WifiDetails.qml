import QtQuick
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: root
    spacing: 6
    property bool active: false

    // ── Metric properties ──────────────────────────────────────
    property string dSsid: ""
    property string dFreq: ""
    property int dSignal: 0
    property int dNoise: -95
    property string dLinkRate: ""
    property string dGateway: ""
    property string dDns: ""
    property real dRouterPing: -1
    property real dInternetPing: -1
    property real dDnsLookup: -1

    // ── Rolling histories (30 samples) ─────────────────────────
    property var signalHist: []
    property var routerPingHist: []
    property var internetPingHist: []
    property var dnsLookupHist: []
    property var noiseHist: []
    property var linkRateHist: []

    // ── Jitter / loss tracking ─────────────────────────────────
    property var routerPingAll: []
    property var internetPingAll: []
    property var routerLossArr: []
    property var internetLossArr: []
    property real routerJitter: 0
    property real internetJitter: 0
    property real routerLoss: 0
    property real internetLoss: 0

    // ── Misc state ─────────────────────────────────────────────
    property string speedTestState: ""
    property bool captiveDetected: false
    property bool signalMsgDismissed: false
    property bool copied: false

    // ── Helpers ────────────────────────────────────────────────
    function pushHist(arr, val) {
        let a = arr.slice();
        a.push(val);
        if (a.length > 30) a.shift();
        return a;
    }

    function calcJitter(arr) {
        if (arr.length < 2) return 0;
        let sum = 0;
        for (let i = 1; i < arr.length; i++)
            sum += Math.abs(arr[i] - arr[i - 1]);
        return sum / (arr.length - 1);
    }

    function calcLoss(arr) {
        if (arr.length === 0) return 0;
        let lost = 0;
        for (let i = 0; i < arr.length; i++)
            if (arr[i] === 0) lost++;
        return (lost / arr.length) * 100;
    }

    function freqBand(freq) {
        let f = parseInt(freq);
        if (f >= 5925) return "6 GHz";
        if (f >= 5000) return "5 GHz";
        return "2.4 GHz";
    }

    function signalColor(signal) {
        if (signal >= -50) return Theme.greenBright;
        if (signal >= -67) return Theme.yellowBright;
        if (signal >= -75) return Theme.orangeBright;
        return Theme.redBright;
    }

    function pingColor(ping) {
        if (ping < 0) return Theme.fg4;
        if (ping < 20) return Theme.greenBright;
        if (ping < 50) return Theme.yellowBright;
        if (ping < 100) return Theme.orangeBright;
        return Theme.redBright;
    }

    function jitterColor(jitter) {
        if (jitter < 5) return Theme.greenBright;
        if (jitter < 15) return Theme.yellowBright;
        if (jitter < 30) return Theme.orangeBright;
        return Theme.redBright;
    }

    function lossColor(loss) {
        if (loss < 1) return Theme.greenBright;
        if (loss < 5) return Theme.yellowBright;
        if (loss < 15) return Theme.orangeBright;
        return Theme.redBright;
    }

    function signalMsg(signal) {
        if (signal >= -50) return "";
        if (signal >= -67) return "Signal is fair — consider moving closer to the router";
        if (signal >= -75) return "Signal is weak — connection may be unreliable";
        return "Signal is very weak — expect drops and slow speeds";
    }

    function resetAll() {
        dSsid = ""; dFreq = ""; dSignal = 0; dNoise = -95;
        dLinkRate = ""; dGateway = ""; dDns = "";
        dRouterPing = -1; dInternetPing = -1; dDnsLookup = -1;
        signalHist = []; routerPingHist = []; internetPingHist = []; dnsLookupHist = [];
        noiseHist = []; linkRateHist = [];
        routerPingAll = []; internetPingAll = [];
        routerLossArr = []; internetLossArr = [];
        routerJitter = 0; internetJitter = 0;
        routerLoss = 0; internetLoss = 0;
        speedTestState = ""; captiveDetected = false;
        signalMsgDismissed = false; copied = false;
        stBaseline = 0; stDownload = 0; stUpload = 0;
        stDlPing = 0; stUlPing = 0;
    }

    // ── Poll timer ─────────────────────────────────────────────
    Timer {
        id: pollTimer
        interval: 3000; running: root.active; repeat: true
        triggeredOnStart: true
        onTriggered: { if (!pollProc.running) pollProc.running = true; }
    }

    // ── Poll process ───────────────────────────────────────────
    Process {
        id: pollProc; running: false
        command: ["bash", "-c",
            "iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}'); " +
            "link=$(iw dev \"$iface\" link 2>/dev/null); " +
            "ssid=$(echo \"$link\" | sed -n 's/.*SSID: //p'); echo \"SSID=$ssid\"; " +
            "freq=$(echo \"$link\" | awk '/freq:/{print $2}'); echo \"FREQ=$freq\"; " +
            "sig=$(echo \"$link\" | awk '/signal:/{print $2}'); echo \"SIGNAL=$sig\"; " +
            "rate=$(echo \"$link\" | sed -n 's/.*tx bitrate: //p'); echo \"LINKRATE=$rate\"; " +
            "gw=$(ip route show default 2>/dev/null | awk '{print $3; exit}'); echo \"GATEWAY=$gw\"; " +
            "dns=$(awk '/^nameserver/{print $2; exit}' /etc/resolv.conf 2>/dev/null); echo \"DNS=$dns\"; " +
            "noise=$(iw dev \"$iface\" survey dump 2>/dev/null | awk '/in use/{f=1} f&&/noise:/{print $2; exit}'); echo \"NOISE=${noise:--95}\"; " +
            "rp=$(ping -c1 -W1 \"$gw\" 2>/dev/null | sed -n 's/.*time=\\([0-9.]*\\).*/\\1/p'); echo \"ROUTERPING=${rp:--1}\"; " +
            "ep=$(ping -c1 -W1 1.1.1.1 2>/dev/null | sed -n 's/.*time=\\([0-9.]*\\).*/\\1/p'); echo \"INTERNETPING=${ep:--1}\"; " +
            "dl=$(dig +noall +stats google.com 2>/dev/null | awk '/Query time:/{print $4}'); echo \"DNSLOOKUP=${dl:--1}\"; " +
            "cp=$(curl -s -m2 http://detectportal.firefox.com/success.txt 2>/dev/null); " +
            "[ \"$cp\" = success ] && echo CAPTIVE=0 || echo CAPTIVE=1"
        ]
        stdout: SplitParser { onRead: (line) => {
            let eq = line.indexOf("=");
            if (eq < 0) return;
            let key = line.substring(0, eq);
            let val = line.substring(eq + 1);
            switch (key) {
            case "SSID": root.dSsid = val; break;
            case "FREQ": root.dFreq = val; break;
            case "SIGNAL":
                root.dSignal = parseInt(val) || 0;
                root.signalHist = root.pushHist(root.signalHist, root.dSignal);
                break;
            case "NOISE": root.dNoise = parseInt(val) || -95; root.noiseHist = root.pushHist(root.noiseHist, root.dNoise); break;
            case "LINKRATE": root.dLinkRate = val; root.linkRateHist = root.pushHist(root.linkRateHist, parseFloat(val) || 0); break;
            case "GATEWAY": root.dGateway = val; break;
            case "DNS": root.dDns = val; break;
            case "ROUTERPING":
                root.dRouterPing = parseFloat(val);
                if (root.dRouterPing >= 0) {
                    root.routerPingHist = root.pushHist(root.routerPingHist, root.dRouterPing);
                    root.routerPingAll = root.pushHist(root.routerPingAll, root.dRouterPing);
                    root.routerLossArr = root.pushHist(root.routerLossArr, 1);
                } else {
                    root.routerLossArr = root.pushHist(root.routerLossArr, 0);
                }
                root.routerJitter = root.calcJitter(root.routerPingAll);
                root.routerLoss = root.calcLoss(root.routerLossArr);
                break;
            case "INTERNETPING":
                root.dInternetPing = parseFloat(val);
                if (root.dInternetPing >= 0) {
                    root.internetPingHist = root.pushHist(root.internetPingHist, root.dInternetPing);
                    root.internetPingAll = root.pushHist(root.internetPingAll, root.dInternetPing);
                    root.internetLossArr = root.pushHist(root.internetLossArr, 1);
                } else {
                    root.internetLossArr = root.pushHist(root.internetLossArr, 0);
                }
                root.internetJitter = root.calcJitter(root.internetPingAll);
                root.internetLoss = root.calcLoss(root.internetLossArr);
                break;
            case "DNSLOOKUP":
                root.dDnsLookup = parseFloat(val);
                if (root.dDnsLookup >= 0)
                    root.dnsLookupHist = root.pushHist(root.dnsLookupHist, root.dDnsLookup);
                break;
            case "CAPTIVE":
                root.captiveDetected = (val === "1");
                break;
            }
        } }
    }

    // ── Captive portal opener ──────────────────────────────────
    Process {
        id: captiveOpenProc; running: false
        command: ["xdg-open", "http://detectportal.firefox.com/canonical.html"]
    }

    // ── Tagline ────────────────────────────────────────────────
    Text { text: "Figure out why your Wi-Fi is bad and fix it."; color: Theme.fg4
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ── Connection header ──────────────────────────────────────
    RowLayout { Layout.fillWidth: true; spacing: 8
        Rectangle { width: 8; height: 8; radius: 4
            color: root.dSsid !== "" ? Theme.greenBright : Theme.fg4 }
        Text { text: root.dSsid || "Not connected"; color: Theme.fg; font.bold: true
            font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize
            Layout.fillWidth: true; elide: Text.ElideRight }
        Rectangle {
            visible: root.dFreq !== ""
            width: freqPillText.implicitWidth + 14; height: 20; radius: Theme.btnRadius
            color: Theme.bg2; border.width: 1; border.color: Theme.bg3
            Text { id: freqPillText; anchors.centerIn: parent
                text: root.freqBand(root.dFreq); color: Theme.fg3
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true }
        }
    }

    // ── Link Rate ──────────────────────────────────────────────
    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Link Rate"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.dLinkRate ? parseFloat(root.dLinkRate).toFixed(0) + " Mbps" : "—"; color: Theme.orangeBright
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70; elide: Text.ElideRight }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.linkRateHist; lineColor: Theme.orangeBright }
    }

    // ── Signal ─────────────────────────────────────────────────
    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Signal"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.dSignal !== 0 ? root.dSignal + " dBm" : "—"
            color: root.dSignal === 0 ? Theme.fg4 : (root.dSignal >= -60 ? Theme.greenBright : (root.dSignal >= -75 ? Theme.orangeBright : Theme.redBright))
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.signalHist
            lineColor: root.dSignal === 0 ? Theme.fg4 : (root.dSignal >= -60 ? Theme.greenBright : (root.dSignal >= -75 ? Theme.orangeBright : Theme.redBright)) }
    }

    // ── Noise ──────────────────────────────────────────────────
    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Noise"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.dNoise + " dBm"; color: Theme.greenBright
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.noiseHist; lineColor: Theme.greenBright }
    }

    // ── Signal advisory ────────────────────────────────────────
    Rectangle {
        visible: root.signalMsg(root.dSignal) !== "" && !root.signalMsgDismissed
        Layout.fillWidth: true
        implicitHeight: sigAdvRow.implicitHeight + 16
        radius: Theme.btnRadius; color: Theme.bg2; border.width: 1; border.color: Theme.bg3

        RowLayout {
            id: sigAdvRow; anchors.left: parent.left; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter; anchors.margins: 8; spacing: 8
            Text { text: root.signalMsg(root.dSignal); color: Theme.fg4; Layout.fillWidth: true
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1; wrapMode: Text.WordWrap }
            Rectangle {
                width: 24; height: 24; radius: Theme.hoverRadius; color: "transparent"
                Rectangle {
                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                    opacity: sigDismissA.pressed ? 0.9 : (sigDismissA.containsMouse ? 0.6 : 0)
                    Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                }
                scale: sigDismissA.pressed ? 0.98 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                transformOrigin: Item.Center
                Text { anchors.centerIn: parent; text: "×"
                    color: sigDismissA.containsMouse ? Theme.fg : Theme.fg4
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                MouseArea { id: sigDismissA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: root.signalMsgDismissed = true }
            }
        }
    }

    // ── Captive portal warning ─────────────────────────────────
    Rectangle {
        visible: root.captiveDetected
        Layout.fillWidth: true
        implicitHeight: captiveRow.implicitHeight + 16
        radius: Theme.btnRadius; color: Theme.bg2; border.width: 1; border.color: Theme.yellowBright

        RowLayout {
            id: captiveRow; anchors.left: parent.left; anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter; anchors.margins: 8; spacing: 8
            Text { text: "⚠ Captive portal detected"; color: Theme.yellowBright; Layout.fillWidth: true
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Rectangle {
                width: openLoginLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                color: "transparent"
                Rectangle {
                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                    opacity: openLoginA.pressed ? 0.9 : (openLoginA.containsMouse ? 0.6 : 0)
                    Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                }
                scale: openLoginA.pressed ? 0.98 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                transformOrigin: Item.Center
                Text { id: openLoginLabel; anchors.centerIn: parent; text: "Open Login Page"
                    color: openLoginA.containsMouse ? Theme.yellowBright : Theme.fg4
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                MouseArea { id: openLoginA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: captiveOpenProc.running = true }
            }
        }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ── Router ─────────────────────────────────────────────────
    Text { text: "Router"; color: Theme.fg4; font.bold: true
        font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize }

    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Ping"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.dRouterPing >= 0 ? root.dRouterPing.toFixed(1) + " ms" : "—"
            color: root.pingColor(root.dRouterPing)
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.routerPingHist; lineColor: root.pingColor(root.dRouterPing) }
    }

    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Jitter"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.routerJitter > 0 ? root.routerJitter.toFixed(1) + " ms" : "—"
            color: root.jitterColor(root.routerJitter)
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.routerPingHist; lineColor: root.jitterColor(root.routerJitter) }
    }

    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Loss"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.routerLoss > 0 ? root.routerLoss.toFixed(1) + "%" : "0%"
            color: root.lossColor(root.routerLoss)
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.routerLossArr; lineColor: root.lossColor(root.routerLoss) }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ── Internet ───────────────────────────────────────────────
    Text { text: "Internet · Connected to 1.1.1.1"; color: Theme.fg4; font.bold: true
        font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize }

    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Ping"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.dInternetPing >= 0 ? root.dInternetPing.toFixed(1) + " ms" : "—"
            color: root.pingColor(root.dInternetPing)
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.internetPingHist; lineColor: root.pingColor(root.dInternetPing) }
    }

    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Jitter"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.internetJitter > 0 ? root.internetJitter.toFixed(1) + " ms" : "—"
            color: root.jitterColor(root.internetJitter)
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.internetPingHist; lineColor: root.jitterColor(root.internetJitter) }
    }

    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Loss"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.internetLoss > 0 ? root.internetLoss.toFixed(1) + "%" : "0%"
            color: root.lossColor(root.internetLoss)
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.internetLossArr; lineColor: root.lossColor(root.internetLoss) }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ── DNS ────────────────────────────────────────────────────
    function setDns(dns) {
        if (dns === "") {
            dnsSetProc.command = ["bash", "-c",
                "iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}'); " +
                "con=$(nmcli -g GENERAL.CONNECTION dev show \"$iface\" 2>/dev/null); " +
                "nmcli con mod \"$con\" ipv4.ignore-auto-dns no ipv4.dns \"\" && " +
                "nmcli con up \"$con\""];
        } else {
            dnsSetProc.command = ["bash", "-c",
                "iface=$(iw dev 2>/dev/null | awk '/Interface/{print $2; exit}'); " +
                "con=$(nmcli -g GENERAL.CONNECTION dev show \"$iface\" 2>/dev/null); " +
                "nmcli con mod \"$con\" ipv4.dns \"" + dns + "\" ipv4.ignore-auto-dns yes && " +
                "nmcli con up \"$con\""];
        }
        dnsSetProc.running = true;
    }

    Process { id: dnsSetProc; running: false }

    Text {
        text: root.dDns === "" ? "DNS" : ("DNS · " + (root.dDns === root.dGateway ? "Router assigned" : "Custom") + " (" + root.dDns + ")")
        color: Theme.fg4; font.bold: true
        font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize
    }

    RowLayout { Layout.fillWidth: true; spacing: 8
        Text { text: "Lookup"; color: Theme.fg3; Layout.preferredWidth: 70
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        Text { text: root.dDnsLookup >= 0 ? root.dDnsLookup.toFixed(0) + " ms" : "—"
            color: root.pingColor(root.dDnsLookup)
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
            horizontalAlignment: Text.AlignRight; Layout.preferredWidth: 70 }
        Item { Layout.preferredWidth: 8 }
        Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 18
            values: root.dnsLookupHist; lineColor: root.pingColor(root.dDnsLookup) }
    }

    RowLayout { Layout.fillWidth: true; spacing: 6
        Repeater { model: [
            { label: "Router", dns: "" },
            { label: "Cloudflare", dns: "1.1.1.1" },
            { label: "Google", dns: "8.8.8.8" }
        ]
            Rectangle {
                required property var modelData
                required property int index
                property bool isCurrent: modelData.dns === "" ? (root.dDns !== "" && root.dDns === root.dGateway) : (root.dDns === modelData.dns)
                width: dnsPillLbl.implicitWidth + 14; height: 24; radius: Theme.btnRadius
                color: isCurrent ? Theme.accent : (dnsPillA.containsMouse ? Theme.bg2 : Theme.bg1)
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                scale: dnsPillA.pressed ? 0.95 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                transformOrigin: Item.Center
                Text { id: dnsPillLbl; anchors.centerIn: parent; text: modelData.label
                    color: isCurrent ? Theme.bg : Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: 10
                    Behavior on color { ColorAnimation { duration: Theme.animHover } } }
                MouseArea { id: dnsPillA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: root.setDns(modelData.dns) }
            }
        }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ── Speed Test ─────────────────────────────────────────────
    property real stBaseline: 0
    property real stDownload: 0
    property real stUpload: 0
    property real stDlPing: 0
    property real stUlPing: 0

    function bloatColor(testPing, baseline) {
        if (baseline <= 0) return Theme.fg4;
        let ratio = testPing / baseline;
        if (ratio < 3 && testPing < 50) return Theme.greenBright;
        if (ratio < 10) return Theme.yellowBright;
        return Theme.redBright;
    }

    function bloatLabel(testPing, baseline) {
        if (baseline <= 0) return "—";
        let ratio = testPing / baseline;
        if (ratio < 3 && testPing < 50) return "Good";
        if (ratio < 10) return "Moderate";
        return "Severe";
    }

    Process {
        id: speedTestProc; running: false
        command: ["bash", "-c",
            "gw=$(ip route show default | awk '{print $3; exit}'); " +
            "bl=$(ping -c3 -W1 \"$gw\" 2>/dev/null | awk -F/ '/rtt/{print $5}'); " +
            "[ -z \"$bl\" ] && bl=0; echo \"STBASELINE=$bl\"; " +
            "ping -c15 -i0.4 -W1 \"$gw\" > /tmp/.whyfi_dlp 2>/dev/null & ppd=$!; " +
            "ds=$(curl -s -o /dev/null -w '%{speed_download}' 'https://speed.cloudflare.com/__down?bytes=25000000' 2>/dev/null); " +
            "kill $ppd 2>/dev/null; wait $ppd 2>/dev/null; " +
            "dp=$(awk -F/ '/rtt/{print $5}' /tmp/.whyfi_dlp 2>/dev/null); " +
            "echo \"DLSPEED=$(echo \"$ds\" | awk '{printf \"%.1f\",$1*8/1000000}')\"; " +
            "echo \"DLPING=${dp:-0}\"; " +
            "ping -c15 -i0.4 -W1 \"$gw\" > /tmp/.whyfi_ulp 2>/dev/null & ppu=$!; " +
            "us=$(dd if=/dev/zero bs=1M count=10 2>/dev/null | " +
            "curl -s -o /dev/null -w '%{speed_upload}' -X POST " +
            "-H 'Content-Type: application/octet-stream' --data-binary @- " +
            "'https://speed.cloudflare.com/__up' 2>/dev/null); " +
            "kill $ppu 2>/dev/null; wait $ppu 2>/dev/null; " +
            "up=$(awk -F/ '/rtt/{print $5}' /tmp/.whyfi_ulp 2>/dev/null); " +
            "echo \"ULSPEED=$(echo \"$us\" | awk '{printf \"%.1f\",$1*8/1000000}')\"; " +
            "echo \"ULPING=${up:-0}\"; " +
            "rm -f /tmp/.whyfi_dlp /tmp/.whyfi_ulp"
        ]
        stdout: SplitParser { onRead: (line) => {
            let eq = line.indexOf("=");
            if (eq < 0) return;
            let key = line.substring(0, eq);
            let val = line.substring(eq + 1);
            switch (key) {
            case "STBASELINE": root.stBaseline = parseFloat(val) || 0; break;
            case "DLSPEED": root.stDownload = parseFloat(val) || 0; break;
            case "DLPING": root.stDlPing = parseFloat(val) || 0; break;
            case "ULSPEED": root.stUpload = parseFloat(val) || 0; break;
            case "ULPING": root.stUlPing = parseFloat(val) || 0; break;
            }
        } }
        onExited: { root.speedTestState = "done"; }
    }

    Text { text: "Speed Test"; color: Theme.fg4; font.bold: true
        font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize }

    // Idle
    Rectangle {
        visible: root.speedTestState === ""
        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
        color: "transparent"
        Rectangle {
            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
            opacity: stRunA.pressed ? 0.9 : (stRunA.containsMouse ? 0.6 : 0.3)
            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
        }
        scale: stRunA.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
        transformOrigin: Item.Center
        Text { anchors.centerIn: parent; text: "Run Speed Test"
            color: stRunA.containsMouse ? Theme.blueBright : Theme.fg
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
        MouseArea { id: stRunA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
            onClicked: {
                root.stBaseline = 0; root.stDownload = 0; root.stUpload = 0;
                root.stDlPing = 0; root.stUlPing = 0;
                root.speedTestState = "running"; speedTestProc.running = true;
            } }
    }

    // Running
    ColumnLayout {
        visible: root.speedTestState === "running"
        Layout.fillWidth: true; spacing: 8; Layout.alignment: Qt.AlignHCenter

        Text { text: "Testing…"; color: Theme.fg
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

    // Done
    ColumnLayout {
        visible: root.speedTestState === "done"
        Layout.fillWidth: true; spacing: 6

        RowLayout { Layout.fillWidth: true; spacing: 12
            RowLayout { Layout.fillWidth: true; spacing: 4
                Text { text: "↓"; color: Theme.greenBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
                Text { text: root.stDownload.toFixed(1); color: Theme.greenBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
                Text { text: "Mbps"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
            }
            RowLayout { Layout.fillWidth: true; spacing: 4
                Text { text: "↑"; color: Theme.greenBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
                Text { text: root.stUpload.toFixed(1); color: Theme.greenBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
                Text { text: "Mbps"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
            }
        }

        RowLayout { Layout.fillWidth: true; spacing: 6
            Rectangle { width: 8; height: 8; radius: 4; color: root.bloatColor(root.stDlPing, root.stBaseline) }
            Text { text: "↓ " + root.bloatLabel(root.stDlPing, root.stBaseline); color: Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
            Rectangle { width: 8; height: 8; radius: 4; color: root.bloatColor(root.stUlPing, root.stBaseline) }
            Text { text: "↑ " + root.bloatLabel(root.stUlPing, root.stBaseline); color: Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        }

        Rectangle {
            width: retestLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
            color: "transparent"; Layout.alignment: Qt.AlignRight
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
                onClicked: {
                    root.stBaseline = 0; root.stDownload = 0; root.stUpload = 0;
                    root.stDlPing = 0; root.stUlPing = 0;
                    root.speedTestState = "running"; speedTestProc.running = true;
                } }
        }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ── Export ──────────────────────────────────────────────────
    function buildReport() {
        let r = "WhyFi Diagnostic Report\n";
        r += "=======================\n";
        r += "SSID: " + dSsid + "\n";
        r += "Frequency: " + dFreq + " MHz (" + freqBand(dFreq) + ")\n";
        r += "Signal: " + dSignal + " dBm\n";
        r += "Noise: " + dNoise + " dBm\n";
        r += "Link Rate: " + dLinkRate + "\n";
        r += "Gateway: " + dGateway + "\n";
        r += "DNS: " + dDns + "\n\n";
        r += "Router Ping: " + (dRouterPing >= 0 ? dRouterPing.toFixed(1) + " ms" : "n/a") + "\n";
        r += "Router Jitter: " + routerJitter.toFixed(1) + " ms\n";
        r += "Router Loss: " + routerLoss.toFixed(1) + "%\n\n";
        r += "Internet Ping: " + (dInternetPing >= 0 ? dInternetPing.toFixed(1) + " ms" : "n/a") + "\n";
        r += "Internet Jitter: " + internetJitter.toFixed(1) + " ms\n";
        r += "Internet Loss: " + internetLoss.toFixed(1) + "%\n\n";
        r += "DNS Lookup: " + (dDnsLookup >= 0 ? dDnsLookup.toFixed(0) + " ms" : "n/a") + "\n";
        if (speedTestState === "done") {
            r += "\nSpeed Test:\n";
            r += "  Download: " + stDownload.toFixed(1) + " Mbps\n";
            r += "  Upload: " + stUpload.toFixed(1) + " Mbps\n";
            r += "  Bufferbloat DL: " + stDlPing.toFixed(1) + " ms (" + bloatLabel(stDlPing, stBaseline) + ")\n";
            r += "  Bufferbloat UL: " + stUlPing.toFixed(1) + " ms (" + bloatLabel(stUlPing, stBaseline) + ")\n";
        }
        if (captiveDetected) r += "\nCaptive portal detected\n";
        return r;
    }

    Process { id: copyProc; running: false }
    Timer { id: copyTimer; interval: 2000; onTriggered: root.copied = false }

    Rectangle {
        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
        color: "transparent"
        Rectangle {
            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
            opacity: root.copied ? 0.5 : (copyA.pressed ? 0.9 : (copyA.containsMouse ? 0.6 : 0.3))
            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
        }
        scale: copyA.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
        transformOrigin: Item.Center
        Text { anchors.centerIn: parent
            text: root.copied ? "Copied!" : "Copy Diagnostic Report"
            color: root.copied ? Theme.greenBright : (copyA.containsMouse ? Theme.blueBright : Theme.fg)
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
        MouseArea { id: copyA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
            enabled: !root.copied
            onClicked: {
                copyProc.command = ["wl-copy", root.buildReport()];
                copyProc.running = true;
                root.copied = true;
                copyTimer.restart();
            } }
    }
}
