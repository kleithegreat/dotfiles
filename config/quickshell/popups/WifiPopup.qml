import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../components" as Components
import "wifi"

FocusScope {
    id: wifiPop
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: wifiContentLoader.item
    readonly property Item focusTarget: wifiPop
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    /*
    Legacy per-popup PanelWindow wrapper retained during the overlay-host migration:
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:wifi"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: {
            if (wifiPop.popupState !== "list") wifiPop.resetState();
            else wifiPop.close();
        }
        MouseArea { anchors.fill: parent; onClicked: wifiPop.close() }
    }
    */

    property string popupState: "list"   // list | detail | password | enterprise | connecting | diagnostics | channels
    property bool listLoading: popupState === "list" && NetworkService.scanning && NetworkService.networksModel.count === 0
    property bool channelLoading: popupState === "channels" && NetworkService.channelScanning

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
            forceActiveFocus();
            contentLoaded = true;
            if (preparePanelForOpen())
                wifiOpenAnim.start();
            resetState();
            NetworkService.scan();
            NetworkService.loadKnown();
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

    // ── UI-driven actions (thin wrappers around NetworkService) ──

    function resetState() {
        popupState = "list";
        NetworkService.resetTarget();
    }

    function connectTo(ssid, security) {
        popupState = NetworkService.connectTo(ssid, security);
    }

    function submitPassword(password) {
        if (!password) return;
        popupState = "connecting";
        NetworkService.submitPassword(password);
    }

    function submitEnterprise(identity, password) {
        if (!identity || !password) return;
        popupState = "connecting";
        NetworkService.submitEnterprise(identity, password);
    }

    function openDetail(ssid, security, signal, isActive) {
        NetworkService.openDetail(ssid, security, signal, isActive);
        popupState = "detail";
    }

    function startDiagnostics() {
        NetworkService.startDiagnostics();
        popupState = "diagnostics";
    }

    function startChannelScan() {
        NetworkService.startChannelScan();
        popupState = "channels";
    }

    // ── React to async backend results ──
    Connections {
        target: NetworkService
        function onConnectSucceeded() { wifiPop.popupState = "list"; }
        function onConnectFailed() { wifiPop.popupState = "list"; }
        function onDisconnected() { wifiPop.popupState = "list"; }
        function onNetworkForgotten() { wifiPop.popupState = "list"; }
    }

    // ── Backdrop ──────────────────────────────────────────────
    Keys.onEscapePressed: {
        if (wifiPop.popupState !== "list") wifiPop.resetState();
        else wifiPop.close();
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
                        if (wifiPop.popupState === "detail")      return "󰖩  " + NetworkService.targetSsid;
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
                        onClicked: NetworkService.scan()

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
                Layout.fillWidth: true; visible: NetworkService.connectError !== ""
                implicitHeight: errorText.implicitHeight
                Text { id: errorText; width: parent.width
                    text: NetworkService.connectError; color: Theme.redBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    opacity: NetworkService.connectError !== "" ? 1 : 0
                    y: NetworkService.connectError !== "" ? 0 : 6
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
                Layout.preferredHeight: NetworkService.networksModel.count === 0 ? 144 : 170
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
                    netModel: NetworkService.networksModel
                    connectedSsid: NetworkService.connectedSsid
                    isCaptivePortal: NetworkService.isCaptivePortal
                    onConnectRequested: (ssid, security) => wifiPop.connectTo(ssid, security)
                    onDetailRequested: (ssid, security, signal, isActive) => wifiPop.openDetail(ssid, security, signal, isActive)
                    onCaptiveLoginRequested: NetworkService.openCaptivePortal()
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
                targetSsid: NetworkService.targetSsid
                targetSecurity: NetworkService.targetSecurity
                targetSignal: NetworkService.targetSignal
                targetIsConnected: NetworkService.targetIsConnected
                targetIsKnown: NetworkService.targetIsKnown
                detailIp: NetworkService.detailIp
                detailGateway: NetworkService.detailGateway
                detailDns: NetworkService.detailDns
                detailFreq: NetworkService.detailFreq
                connectError: NetworkService.connectError
                onConnectRequested: (ssid, security) => wifiPop.connectTo(ssid, security)
                onDisconnectRequested: NetworkService.disconnect()
                onForgetRequested: NetworkService.forgetNetwork()
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
                targetSsid: NetworkService.targetSsid
                connectError: NetworkService.connectError
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
                targetSsid: NetworkService.targetSsid
                connectError: NetworkService.connectError
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
                targetSsid: NetworkService.targetSsid
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
                diagLoading: NetworkService.diagLoading
                speedTestRunning: NetworkService.speedTestRunning
                connectedSsid: NetworkService.connectedSsid
                exportCopied: NetworkService.exportCopied
                diagBand: NetworkService.diagBand
                diagSignal: NetworkService.diagSignal
                diagNoise: NetworkService.diagNoise
                diagLinkRate: NetworkService.diagLinkRate
                diagGateway: NetworkService.diagGateway
                diagGwPing: NetworkService.diagGwPing
                diagGwJitter: NetworkService.diagGwJitter
                diagGwLoss: NetworkService.diagGwLoss
                diagNetPing: NetworkService.diagNetPing
                diagNetJitter: NetworkService.diagNetJitter
                diagNetLoss: NetworkService.diagNetLoss
                diagDnsServer: NetworkService.diagDnsServer
                diagDnsTime: NetworkService.diagDnsTime
                diagDownload: NetworkService.diagDownload
                diagUpload: NetworkService.diagUpload
                diagBufferbloat: NetworkService.diagBufferbloat
                diagBufferbloatOk: NetworkService.diagBufferbloatOk
                diagWifiStandard: NetworkService.diagWifiStandard
                histSignal: NetworkService.histSignal
                histNoise: NetworkService.histNoise
                histGwPing: NetworkService.histGwPing
                histGwJitter: NetworkService.histGwJitter
                histGwLoss: NetworkService.histGwLoss
                histNetPing: NetworkService.histNetPing
                histNetJitter: NetworkService.histNetJitter
                histNetLoss: NetworkService.histNetLoss
                histDnsTime: NetworkService.histDnsTime
                onSpeedTestRequested: NetworkService.startSpeedTest()
                onChannelScanRequested: wifiPop.startChannelScan()
                onDnsChanged: (server) => NetworkService.switchDns(server)
                onExportRequested: NetworkService.exportReport()
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
                    channelModel: NetworkService.channelEntriesModel
                    currentChannel: NetworkService.currentChannel
                    currentBand: NetworkService.currentBand
                    scanning: NetworkService.channelScanning
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
