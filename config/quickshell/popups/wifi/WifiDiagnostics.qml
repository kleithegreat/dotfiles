import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Item {
    id: root

    required property bool diagLoading
    required property bool speedTestRunning
    required property string connectionType
    required property string connectedLabel
    required property bool exportCopied
    required property string ethernetLinkSpeed
    required property string ethernetDuplex
    required property bool ethernetCarrierDetected

    required property string diagBand
    required property string diagSignal
    required property string diagNoise
    required property string diagLinkRate
    required property string diagGateway
    required property string diagGwPing
    required property string diagGwJitter
    required property string diagGwLoss
    required property string diagNetPing
    required property string diagNetJitter
    required property string diagNetLoss
    required property string diagDnsServer
    required property string diagDnsTime
    required property string diagDownload
    required property string diagUpload
    required property string diagBufferbloat
    required property bool diagBufferbloatOk
    required property string diagWifiStandard

    required property var histSignal
    required property var histNoise
    required property var histGwPing
    required property var histGwJitter
    required property var histGwLoss
    required property var histNetPing
    required property var histNetJitter
    required property var histNetLoss
    required property var histDnsTime

    signal speedTestRequested()
    signal channelScanRequested()
    signal dnsChanged(string server)
    signal exportRequested()
    signal rerunRequested()

    readonly property int metricLabelWidth: 50
    readonly property int metricValueWidth: 65
    readonly property int ethernetValueWidth: 80

    // Recomputes reactively: qualityScore() only reads root properties.
    readonly property int quality: qualityScore()

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
    function dnsColor(ms) {
        // Matches NetworkService.exportReport's lookup grading (30/100 ms).
        let v = parseFloat(ms);
        if (isNaN(v)) return Theme.fg4;
        if (v <= 30) return Theme.greenBright;
        if (v <= 100) return Theme.yellowBright;
        return Theme.redBright;
    }
    function lossColor(pct) {
        let v = parseFloat(pct);
        if (isNaN(v)) return Theme.fg4;
        if (v === 0) return Theme.greenBright;
        if (v <= 2) return Theme.yellowBright;
        return Theme.redBright;
    }

    function qualityScore() {
        let score = 100;
        let hasData = false;

        let sig = parseInt(root.diagSignal);
        if (!isNaN(sig)) {
            hasData = true;
            let sigScore = Math.max(0, Math.min(100, ((sig + 90) / 60) * 100));
            score = Math.min(score, sigScore);
        }

        let gwP = parseFloat(root.diagGwPing);
        if (!isNaN(gwP)) {
            hasData = true;
            let pingScore = Math.max(0, Math.min(100, 100 - gwP));
            score = Math.min(score, pingScore);
        }

        let netP = parseFloat(root.diagNetPing);
        if (!isNaN(netP)) {
            hasData = true;
            let netScore = Math.max(0, Math.min(100, 100 - (netP / 2)));
            score = Math.min(score, netScore);
        }

        let gwL = parseFloat(root.diagGwLoss);
        if (!isNaN(gwL) && gwL > 0) {
            hasData = true;
            score = Math.min(score, Math.max(0, 100 - gwL * 20));
        }
        let netL = parseFloat(root.diagNetLoss);
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

    // Sparkline component
    Component {
        id: sparklineComponent
        Canvas {
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

    // Metric row: label, optional sparkline of hist, colored value.
    component DiagMetricRow: RowLayout {
        id: metricRow

        required property string label
        required property string value
        required property var hist
        property string unit: ""
        property var colorFor: null
        property real minVal: NaN
        property real maxVal: NaN

        readonly property bool hasValue: metricRow.value !== "" && metricRow.value !== "--"
        readonly property color valueColor: metricRow.colorFor ? metricRow.colorFor(metricRow.value) : Theme.greenBright

        Layout.fillWidth: true; spacing: 6

        Text { text: metricRow.label; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            Layout.preferredWidth: root.metricLabelWidth }
        Loader {
            Layout.fillWidth: true; Layout.preferredHeight: 20
            active: metricRow.hist.length >= 2
            sourceComponent: sparklineComponent
            onLoaded: {
                item.dataPoints = Qt.binding(() => metricRow.hist);
                item.lineColor = Qt.binding(() => metricRow.valueColor);
                item.minVal = metricRow.minVal;
                item.maxVal = metricRow.maxVal;
            }
        }
        Item { visible: metricRow.hist.length < 2; Layout.fillWidth: true }
        Text {
            text: metricRow.hasValue ? metricRow.value + metricRow.unit : "--"
            color: metricRow.hasValue ? metricRow.valueColor : Theme.fg4
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            Layout.preferredWidth: root.metricValueWidth; horizontalAlignment: Text.AlignRight
        }
    }

    // Skeleton loading
    Column {
        visible: root.diagLoading
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

    // Diagnostics results
    Components.WheelFlickable {
        visible: !root.diagLoading
        anchors.fill: parent
        contentHeight: diagCol.implicitHeight; clip: true

        ColumnLayout {
            id: diagCol; width: parent.width; spacing: 6

            // Quality score
            RowLayout {
                visible: root.quality >= 0
                Layout.fillWidth: true; spacing: 8; Layout.bottomMargin: 4

                Text {
                    text: root.quality.toString()
                    color: root.qualityColor(root.quality)
                    font.family: Theme.fontFamily; font.pixelSize: 28; font.bold: true
                }
                ColumnLayout { spacing: 1; Layout.fillWidth: true
                    Text {
                        text: root.qualityLabel(root.quality)
                        color: root.qualityColor(root.quality)
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                    }
                    Text { text: "Connection Quality"; color: Theme.fg4
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini }
                }
            }

            // Network header
            RowLayout { Layout.fillWidth: true; spacing: 6
                Text { text: root.connectedLabel; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                Rectangle {
                    visible: root.connectionType === "wifi" && root.diagBand !== "" && root.diagBand !== "unknown"
                    width: bandLabel.implicitWidth + 10; height: 18; radius: 4; color: Theme.bg3
                    Text { id: bandLabel; anchors.centerIn: parent; text: root.diagBand; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMicro }
                }
                Rectangle {
                    visible: root.connectionType === "ethernet"
                    width: ethLabel.implicitWidth + 10; height: 18; radius: 4; color: Theme.bg3
                    Text { id: ethLabel; anchors.centerIn: parent; text: "Ethernet"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMicro }
                }
            }
            // Wi-Fi standard
            Text {
                visible: root.connectionType === "wifi" && root.diagWifiStandard !== "" && root.diagWifiStandard !== "unknown"
                text: root.diagWifiStandard
                color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
            }
            // Upgrade warning for old standards
            Rectangle {
                visible: root.connectionType === "wifi" && (root.diagWifiStandard.indexOf("Wi-Fi 4") >= 0 || root.diagWifiStandard.indexOf("802.11g") >= 0)
                Layout.fillWidth: true; height: stdWarnText.implicitHeight + 8; radius: Theme.btnRadius
                color: Theme.bg2; border.width: 1; border.color: Theme.yellowBright
                Text {
                    id: stdWarnText
                    anchors.centerIn: parent; width: parent.width - 12
                    text: root.diagBand === "2.4 GHz"
                        ? "Using an older Wi-Fi standard \u2014 try connecting to a 5 GHz network for better speeds."
                        : "Using an older Wi-Fi standard. Your router may need a firmware update."
                    color: Theme.yellowBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
                    wrapMode: Text.WordWrap
                }
            }

            // Link Rate
            RowLayout { visible: root.connectionType === "wifi"; Layout.fillWidth: true
                Text { text: "Link Rate"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
                Text { text: (root.diagLinkRate && root.diagLinkRate !== "--") ? root.diagLinkRate + " Mbps" : "--"
                    color: (root.diagLinkRate && root.diagLinkRate !== "--") ? Theme.greenBright : Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.preferredWidth: root.metricValueWidth; horizontalAlignment: Text.AlignRight }
            }

            DiagMetricRow {
                visible: root.connectionType === "wifi"
                label: "Signal"; value: root.diagSignal; unit: " dBm"; hist: root.histSignal
                colorFor: (v) => root.signalColor(v)
                minVal: -90; maxVal: -30
            }
            Text {
                visible: {
                    if (root.connectionType !== "wifi")
                        return false;
                    let v = parseInt(root.diagSignal);
                    return !isNaN(v) && v < -50;
                }
                text: {
                    let v = parseInt(root.diagSignal);
                    if (v >= -60) return "Decent signal. Moving closer to your router could improve speeds.";
                    if (v >= -70) return "Weak signal \u2014 functional but not ideal. Try moving closer or adjusting router placement.";
                    return "Very weak signal. Walls and distance are significantly degrading your connection.";
                }
                color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
                wrapMode: Text.WordWrap; Layout.fillWidth: true
                opacity: 0.8
            }

            DiagMetricRow {
                visible: root.connectionType === "wifi"
                label: "Noise"; value: root.diagNoise; unit: " dBm"; hist: root.histNoise
                minVal: -100; maxVal: -60
            }

            RowLayout { visible: root.connectionType === "ethernet"; Layout.fillWidth: true
                Text { text: "Link Speed"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
                Text { text: root.ethernetLinkSpeed !== "" ? root.ethernetLinkSpeed + " Mbps" : "--"
                    color: root.ethernetLinkSpeed !== "" ? Theme.greenBright : Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.preferredWidth: root.ethernetValueWidth; horizontalAlignment: Text.AlignRight }
            }
            RowLayout { visible: root.connectionType === "ethernet"; Layout.fillWidth: true
                Text { text: "Duplex"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
                Text { text: root.ethernetDuplex || "--"
                    color: root.ethernetDuplex !== "" ? Theme.greenBright : Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.preferredWidth: root.ethernetValueWidth; horizontalAlignment: Text.AlignRight }
            }
            RowLayout { visible: root.connectionType === "ethernet"; Layout.fillWidth: true
                Text { text: "Carrier"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
                Text { text: root.ethernetCarrierDetected ? "Detected" : "Not detected"
                    color: root.ethernetCarrierDetected ? Theme.greenBright : Theme.redBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.preferredWidth: root.ethernetValueWidth; horizontalAlignment: Text.AlignRight }
            }

            // Router section
            Components.Divider { Layout.topMargin: 4 }
            RowLayout { spacing: 6
                Components.Icon { source: "../icons/router.svg"; color: Theme.fg }
                Text { text: "Router" + (root.diagGateway && root.diagGateway !== "--" ? " \u00b7 " + root.diagGateway : ""); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            }

            DiagMetricRow { label: "Ping"; value: root.diagGwPing; unit: " ms"; hist: root.histGwPing; colorFor: (v) => root.pingColor(v) }
            DiagMetricRow { label: "Jitter"; value: root.diagGwJitter; unit: " ms"; hist: root.histGwJitter; colorFor: (v) => root.pingColor(v) }
            DiagMetricRow { label: "Loss"; value: root.diagGwLoss; unit: "%"; hist: root.histGwLoss; colorFor: (v) => root.lossColor(v) }

            // Internet section
            Components.Divider { Layout.topMargin: 4 }
            RowLayout { spacing: 6
                Components.Icon { source: "../icons/wifi.svg"; color: Theme.fg }
                Text { text: "Internet \u00b7 1.1.1.1"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            }

            DiagMetricRow { label: "Ping"; value: root.diagNetPing; unit: " ms"; hist: root.histNetPing; colorFor: (v) => root.pingColor(v) }
            DiagMetricRow { label: "Jitter"; value: root.diagNetJitter; unit: " ms"; hist: root.histNetJitter; colorFor: (v) => root.pingColor(v) }
            DiagMetricRow { label: "Loss"; value: root.diagNetLoss; unit: "%"; hist: root.histNetLoss; colorFor: (v) => root.lossColor(v) }

            // DNS section
            Components.Divider { Layout.topMargin: 4 }
            RowLayout { spacing: 6
                Components.Icon { source: "../icons/world.svg"; color: Theme.fg }
                Text { text: "DNS" + (root.diagDnsServer && root.diagDnsServer !== "--" ? " \u00b7 " + root.diagDnsServer : ""); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            }

            DiagMetricRow { label: "Lookup"; value: root.diagDnsTime; unit: " ms"; hist: root.histDnsTime; colorFor: (v) => root.dnsColor(v) }

            // DNS quick-switch buttons
            RowLayout {
                Layout.fillWidth: true; spacing: 6; Layout.topMargin: 4
                opacity: NetworkService.dnsSwitchPending ? Theme.pendingOpacity : 1
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text { text: "Switch:"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini }

                Repeater {
                    model: [
                        { label: "Router", value: "auto" },
                        { label: "Google", value: "8.8.8.8" },
                        { label: "Cloudflare", value: "1.1.1.1" }
                    ]

                    Rectangle {
                        id: dnsBtn
                        required property var modelData
                        property bool isCurrent: NetworkService.dnsSelection === modelData.value
                        width: dnsBtnLabel.implicitWidth + 16; height: 24; radius: Theme.btnRadius
                        color: isCurrent ? Theme.accent : "transparent"
                        border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                        Rectangle {
                            visible: !dnsBtn.isCurrent
                            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                            opacity: dnsBtnA.pressed ? 0.9 : (dnsBtnA.containsMouse ? 0.6 : 0.3)
                            Behavior on opacity { Components.StdAnim { duration: Theme.animHover } }
                        }
                        Text { id: dnsBtnLabel; anchors.centerIn: parent; text: dnsBtn.modelData.label
                            color: dnsBtn.isCurrent ? Theme.bg : (dnsBtnA.containsMouse ? Theme.fg : Theme.fg4); font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } } }
                        Components.HoverLayer { id: dnsBtnA; hoverOpacity: 0; pressedOpacity: 0
                            disabled: NetworkService.dnsSwitchPending
                            onClicked: root.dnsChanged(dnsBtn.modelData.value) }
                    }
                }
            }

            // Scan Channels
            Components.Divider { visible: root.connectionType === "wifi"; Layout.topMargin: 4 }
            Rectangle {
                visible: root.connectionType === "wifi"
                Layout.fillWidth: true; height: Theme.btnHeight; radius: Theme.btnRadius
                color: "transparent"
                Components.HoverLayer {
                    id: chanScanA
                    idleOpacity: 0.3
                    onClicked: root.channelScanRequested()

                    Row { anchors.centerIn: parent; spacing: 6
                        Components.Icon { source: "../icons/radar.svg"; color: chanScanA.containsMouse ? Theme.blueBright : Theme.fg4; anchors.verticalCenter: parent.verticalCenter
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                        }
                        Text { text: "Scan Channels"; color: chanScanA.containsMouse ? Theme.blueBright : Theme.fg4; anchors.verticalCenter: parent.verticalCenter
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                        }
                    }
                }
            }

            // Speed Test section
            Components.Divider { Layout.topMargin: 4 }
            RowLayout { spacing: 6
                Components.Icon { source: "../icons/speed.svg"; color: Theme.fg }
                Text { text: "Speed Test"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            }

            RowLayout {
                visible: root.diagDownload !== "" && !root.speedTestRunning
                Layout.fillWidth: true; spacing: 12
                ColumnLayout { spacing: 2
                    Text { text: root.diagDownload || "--"; color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
                    Text { text: "\u2193 Mbps"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini }
                }
                ColumnLayout { spacing: 2
                    Text { text: root.diagUpload || "--"; color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true }
                    Text { text: "\u2191 Mbps"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini }
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: retestLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: retestA
                        onClicked: root.speedTestRequested()

                        Text { id: retestLabel; anchors.centerIn: parent; text: "Retest"; color: retestA.containsMouse ? Theme.blueBright : Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } } }
                    }
                }
            }

            Rectangle {
                visible: root.speedTestRunning
                Layout.fillWidth: true
                radius: Theme.btnRadius
                color: Theme.bg2
                border.width: 1
                border.color: Theme.bg3
                implicitHeight: speedStatusCol.implicitHeight + 14

                ColumnLayout {
                    id: speedStatusCol
                    anchors.fill: parent
                    anchors.margins: 7
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Rectangle {
                            width: 8; height: 8; radius: 4
                            color: Theme.blueBright
                            SequentialAnimation on opacity {
                                running: root.speedTestRunning
                                loops: Animation.Infinite
                                NumberAnimation { from: 1; to: 0.3; duration: 700 }
                                NumberAnimation { from: 0.3; to: 1; duration: 700 }
                            }
                        }

                        Text {
                            text: "Running speed test"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: "15-30s"
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMini
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "Measuring download, upload, and latency under load."
                        color: Theme.fg4
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeMini
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Bufferbloat result
            RowLayout {
                visible: root.diagBufferbloat !== "" && !root.speedTestRunning
                Layout.fillWidth: true; spacing: 6
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: root.diagBufferbloatOk ? Theme.greenBright : Theme.redBright
                }
                Text {
                    text: root.diagBufferbloat
                    color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }

            Rectangle {
                visible: root.diagDownload === "" || root.speedTestRunning
                Layout.fillWidth: true; height: Theme.btnHeight; radius: Theme.btnRadius
                color: "transparent"
                Components.HoverLayer {
                    id: speedBtnA
                    idleOpacity: 0.3
                    disabled: root.speedTestRunning
                    onClicked: root.speedTestRequested()

                    Text {
                        anchors.centerIn: parent
                        text: root.speedTestRunning ? "Running Speed Test\u2026" : "Run Speed Test"
                        color: speedBtnA.containsMouse ? Theme.blueBright : Theme.fg4
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                        SequentialAnimation on opacity {
                            running: root.speedTestRunning; loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.4; duration: 600 }
                            NumberAnimation { from: 0.4; to: 1; duration: 600 }
                        }
                    }
                }
            }

            // Bottom actions
            Components.Divider {}
            RowLayout {
                Layout.fillWidth: true; spacing: 6

                Rectangle {
                    Layout.fillWidth: true; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: exportA
                        onClicked: root.exportRequested()

                        Row { anchors.centerIn: parent; spacing: 6
                            Components.Icon { source: root.exportCopied ? "../icons/circle-check.svg" : "../icons/info-circle.svg"; anchors.verticalCenter: parent.verticalCenter
                                color: root.exportCopied ? Theme.greenBright : (exportA.containsMouse ? Theme.blueBright : Theme.fg4)
                                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                            }
                            Text { text: root.exportCopied ? "Copied" : "Export Report"; anchors.verticalCenter: parent.verticalCenter
                                color: root.exportCopied ? Theme.greenBright : (exportA.containsMouse ? Theme.blueBright : Theme.fg4)
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: rerunA
                        onClicked: root.rerunRequested()

                        Text { anchors.centerIn: parent; text: "\u21bb Rerun"; color: rerunA.containsMouse ? Theme.blueBright : Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } } }
                    }
                }
            }
        }
    }
}
