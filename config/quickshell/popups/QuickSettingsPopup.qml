import qs
import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../components" as Components

FocusScope {
    id: qsPop
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    property bool suppressHeightAnimation: false
    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: qsContentLoader.item
    readonly property Item focusTarget: qsPop
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    // Expand-to-full-page signals
    signal settingsRequested()
    signal wifiExpandRequested()
    signal bluetoothExpandRequested()
    signal vpnExpandRequested()
    signal dndExpandRequested()
    signal powerProfileExpandRequested()

    property bool wifiConnected: NetworkService.connectedSsid !== ""
    property string wifiSsid: NetworkService.connectedSsid
    property real panelHeightHint: 360
    readonly property int metricLabelWidth: Math.max(Theme.fontSize * 3, 32)

    // ── Battery ──
    property real batPct: {
        let r = UPower.displayDevice.percentage;
        return (r <= 1.0 && r > 0) ? r * 100 : r;
    }
    property bool batCharging: UPower.displayDevice.state === UPowerDeviceState.Charging
                                || UPower.displayDevice.state === UPowerDeviceState.FullyCharged
    property bool batPresent: UPower.displayDevice.isPresent

    function batIcon() {
        if (batCharging) return "../icons/battery-charging.svg";
        if (batPct > 90) return "../icons/battery-full.svg";
        if (batPct > 70) return "../icons/battery-high.svg";
        if (batPct > 50) return "../icons/battery-medium.svg";
        return "../icons/battery-low.svg";
    }

    // ── Power profile cycling ──
    function cyclePowerProfile() {
        let cur = PowerProfileService.currentProfile;
        if (cur === "balanced") PowerProfileService.setProfile("performance");
        else if (cur === "performance") PowerProfileService.setProfile("power-saver");
        else PowerProfileService.setProfile("balanced");
    }

    // ── Standard popup lifecycle ──
    function preparePanelForOpen() {
        let item = qsContentLoader.item;
        if (!item)
            return false;
        item.opacity = 0;
        item.scale = 0.92;
        return true;
    }

    onActiveChanged: {
        if (active) {
            suppressHeightAnimation = true;
            forceActiveFocus();
            contentLoaded = true;
            NetworkService.refreshSummary();
            BluetoothService.refreshSummary();
            BrightnessService.refresh();
            PowerProfileService.detect();
            VpnService.refresh();
            if (preparePanelForOpen())
                qsOpenAnim.start();
        } else if (!closing) {
            if (qsContentLoader.item) {
                suppressHeightAnimation = true;
                closing = true;
                qsCloseAnim.start();
            } else {
                suppressHeightAnimation = false;
                closing = false;
            }
        }
    }

    SequentialAnimation {
        id: qsOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: qsContentLoader.item; property: "opacity"; to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            SequentialAnimation {
                PauseAnimation { duration: 40 }
                Components.Anim {
                    target: qsContentLoader.item; property: "scale"; to: 1.0
                    duration: Theme.animPopupIn - 40
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveEmphasizedEnter
                }
            }
        }
        onFinished: {
            if (qsPop.active && !qsPop.closing)
                qsPop.suppressHeightAnimation = false;
        }
    }

    SequentialAnimation {
        id: qsCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: qsContentLoader.item; property: "opacity"; to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: qsContentLoader.item; property: "scale"; to: 0.92
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction {
            script: {
                qsPop.closing = false;
                qsPop.suppressHeightAnimation = false;
            }
        }
    }

    Keys.onEscapePressed: qsPop.close()

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin
        anchors.rightMargin: Theme.gapOut
        width: qsContentLoader.width
        height: qsContentLoader.height
        visible: qsPop.overlayVisible && !qsPop.closing && height > 0 && (!qsContentLoader.item || qsContentLoader.item.opacity < 1)
        opacity: qsContentLoader.item ? Math.max(0, 1 - qsContentLoader.item.opacity) : 1
        radius: Theme.popupRadius
        color: Theme.bg1
        border.width: 1
        border.color: Theme.bg3
        Behavior on opacity { Components.Anim { duration: Theme.animHover } }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Loader {
        id: qsContentLoader
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: 360
        height: qsPop.overlayVisible ? qsPop.panelHeightHint : 0
        active: qsPop.contentLoaded || qsPop.active || qsPop.closing
        asynchronous: true
        sourceComponent: qsPanelComponent
        Behavior on height {
            enabled: !qsPop.suppressHeightAnimation
            Components.Anim {
                duration: Theme.animHeightResize
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }

        onLoaded: {
            qsPop.panelHeightHint = item.implicitHeight;
            item.opacity = 0;
            item.scale = 0.92;
            if (qsPop.active)
                qsOpenAnim.start();
        }
    }

    Connections {
        target: qsContentLoader.item

        function onImplicitHeightChanged() {
            qsPop.panelHeightHint = qsContentLoader.item.implicitHeight;
        }
    }

    Component {
        id: qsPanelComponent

        Rectangle {
            id: qsPanel
            anchors.fill: parent
            implicitHeight: Math.min(qsMainCol.implicitHeight + Theme.popupPadding * 2, qsPop.height - Theme.popupTopMargin - Theme.gapOut * 2)
            radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
            opacity: 0; scale: 0.92
            transformOrigin: Item.TopRight
            MouseArea { anchors.fill: parent }

            Components.WheelFlickable {
                id: qsScroll
                anchors.fill: parent
                anchors.margins: Theme.popupPadding
                contentWidth: width
                contentHeight: qsMainCol.implicitHeight
                clip: true

                ColumnLayout {
                    id: qsMainCol
                    width: qsScroll.width
                spacing: Theme.sectionSpacing

                // ═══════════════════ Toggle Tile Grid ═══════════════════

                Grid {
                    id: tileGrid
                    Layout.fillWidth: true
                    columns: 2; rowSpacing: 8; columnSpacing: 8

                    Repeater {
                        model: {
                            var tiles = [];
                            if (HostCapabilities.hasWifi) tiles.push({ key: "wifi", label: "Wi-Fi" });
                            tiles.push({ key: "bluetooth", label: "Bluetooth" });
                            tiles.push({ key: "vpn", label: "VPN" });
                            tiles.push({ key: "dnd", label: "Do Not Disturb" });
                            tiles.push({ key: "idle", label: "Idle Inhibit", expandable: false });
                            if (HostCapabilities.hasPowerProfiles) tiles.push({ key: "power", label: "Power Profile" });
                            return tiles;
                        }

                        Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            width: (tileGrid.width - tileGrid.columnSpacing) / 2
                            height: 56
                            radius: Theme.hoverRadius
                            color: "transparent"

                            property bool isActive: {
                                switch (modelData.key) {
                                case "wifi": return NetworkService.wifiEnabled;
                                case "bluetooth": return BluetoothService.powered;
                                case "vpn": return VpnService.mullvadState === "connected" || VpnService.mullvadState === "connecting";
                                case "dnd": return NotificationService.doNotDisturb;
                                case "idle": return IdleInhibitService.inhibited;
                                case "power": return PowerProfileService.currentProfile !== "balanced" && PowerProfileService.currentProfile !== "unknown";
                                default: return false;
                                }
                            }

                            readonly property bool canExpand: modelData.expandable !== false

                            property bool isPending: {
                                switch (modelData.key) {
                                case "wifi": return NetworkService.wifiRadioBusy;
                                case "bluetooth": return BluetoothService.powerBusy;
                                case "vpn": return VpnService.mullvadBusy;
                                case "power": return PowerProfileService.pendingProfile !== "";
                                default: return false;
                                }
                            }

                            property string tileIcon: {
                                switch (modelData.key) {
                                case "wifi": return qsPop.wifiConnected ? "../icons/wifi.svg" : "../icons/wifi-off.svg";
                                case "bluetooth":
                                    if (!BluetoothService.powered) return "../icons/bluetooth-off.svg";
                                    return BluetoothService.connectedName !== "" ? "../icons/bluetooth-connected.svg" : "../icons/bluetooth-on.svg";
                                case "vpn": return "../icons/shield-lock.svg";
                                case "dnd": return NotificationService.doNotDisturb ? "../icons/bell-off.svg" : "../icons/bell.svg";
                                case "idle": return "../icons/zzz.svg";
                                case "power":
                                    if (PowerProfileService.currentProfile === "performance") return "../icons/flame.svg";
                                    if (PowerProfileService.currentProfile === "power-saver") return "../icons/leaf.svg";
                                    return "../icons/speed.svg";
                                default: return "";
                                }
                            }

                            property string tileSublabel: {
                                switch (modelData.key) {
                                case "wifi":
                                    if (NetworkService.wifiRadioBusy)
                                        return NetworkService.wifiEnabled ? "Turning on…" : "Turning off…";
                                    if (!NetworkService.wifiRadioReady) return "Checking…";
                                    if (!NetworkService.wifiEnabled) return "Off";
                                    return qsPop.wifiConnected ? qsPop.wifiSsid : "Not connected";
                                case "bluetooth":
                                    if (BluetoothService.powerBusy)
                                        return BluetoothService.powered ? "Turning on…" : "Turning off…";
                                    if (!BluetoothService.powered) return "Off";
                                    return BluetoothService.connectedName !== "" ? BluetoothService.connectedName : "On";
                                case "vpn":
                                    if (VpnService.mullvadState === "disconnecting") return "Disconnecting…";
                                    if (VpnService.mullvadState === "connected")
                                        return VpnService.mullvadCity || VpnService.mullvadCountry || "Connected";
                                    if (VpnService.mullvadState === "connecting") return "Connecting…";
                                    return "Off";
                                case "dnd": return NotificationService.doNotDisturb ? "On" : "Off";
                                case "idle": return IdleInhibitService.inhibited ? "On" : "Off";
                                case "power":
                                    if (PowerProfileService.currentProfile === "performance") return "Performance";
                                    if (PowerProfileService.currentProfile === "power-saver") return "Power Saver";
                                    if (PowerProfileService.currentProfile === "balanced") return "Balanced";
                                    return PowerProfileService.currentProfile;
                                default: return "";
                                }
                            }

                            property color tileActiveColor: {
                                switch (modelData.key) {
                                case "dnd": return Theme.orangeBright;
                                case "idle": return Theme.yellowBright;
                                case "power":
                                    if (PowerProfileService.currentProfile === "performance") return Theme.redBright;
                                    if (PowerProfileService.currentProfile === "power-saver") return Theme.greenBright;
                                    return Theme.blueBright;
                                default: return Theme.blueBright;
                                }
                            }

                            function tileToggle() {
                                switch (modelData.key) {
                                case "wifi": NetworkService.toggleWifiRadio(); break;
                                case "bluetooth": BluetoothService.togglePower(); break;
                                case "vpn":
                                    if (VpnService.mullvadState === "connected" || VpnService.mullvadState === "connecting")
                                        VpnService.mullvadDisconnect();
                                    else
                                        VpnService.mullvadConnect();
                                    break;
                                case "dnd": NotificationService.toggleDnd(); break;
                                case "idle": IdleInhibitService.toggle(); break;
                                case "power": qsPop.cyclePowerProfile(); break;
                                }
                            }

                            function tileExpand() {
                                switch (modelData.key) {
                                case "wifi": qsPop.wifiExpandRequested(); break;
                                case "bluetooth": qsPop.bluetoothExpandRequested(); break;
                                case "vpn": qsPop.vpnExpandRequested(); break;
                                case "dnd": qsPop.dndExpandRequested(); break;
                                case "power": qsPop.powerProfileExpandRequested(); break;
                                }
                            }

                            // ── Tile visuals ──

                            opacity: tile.isPending ? 0.72 : 1
                            Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: tile.isActive
                                    ? Qt.rgba(tile.tileActiveColor.r, tile.tileActiveColor.g, tile.tileActiveColor.b, 0.15)
                                    : Theme.bg2
                                Behavior on color {
                                    Components.CAnim {
                                        duration: Theme.animSpring
                                        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: "transparent"
                                border.width: tile.isActive ? 1 : 0; border.color: tile.tileActiveColor
                                opacity: tile.isActive ? 0.5 : 0
                                Behavior on opacity {
                                    Components.Anim {
                                        duration: Theme.animSpring
                                        easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                            }

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius
                                color: Theme.fg
                                opacity: tileMainArea.containsMouse
                                    ? (tileMainArea.pressed ? 0.08 : 0.04)
                                    : 0
                                Behavior on opacity { Components.Anim { duration: Theme.animHover } }
                            }

                            scale: tileMainArea.pressed ? 0.97 : 1.0
                            Behavior on scale { Components.Anim { duration: Theme.animMicro } }

                            MouseArea {
                                id: tileMainArea
                                anchors.fill: parent
                                enabled: !tile.isPending
                                hoverEnabled: true
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: tile.tileToggle()
                            }

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 4; spacing: 6

                                Components.Icon {
                                    source: tile.tileIcon
                                    color: tile.isActive ? tile.tileActiveColor : Theme.fg4
                                    Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true; spacing: 0
                                    Text {
                                        text: tile.modelData.label
                                        color: tile.isActive ? Theme.fg : Theme.fg2
                                        font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall
                                        font.bold: tile.isActive
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                    Text {
                                        text: tile.tileSublabel
                                        color: Theme.fg4
                                        font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall - 1
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                }

                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    visible: tile.canExpand
                                    color: expandBtnArea.containsMouse
                                        ? (expandBtnArea.pressed ? Theme.bg3 : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08))
                                        : "transparent"
                                    Behavior on color { Components.CAnim { duration: Theme.animHover } }

                                    Text {
                                        anchors.centerIn: parent; text: ">"
                                        color: expandBtnArea.containsMouse ? Theme.fg : Theme.fg4
                                        font.family: Theme.fontFamily; font.pixelSize: 10
                                        Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                    }

                                    MouseArea {
                                        id: expandBtnArea
                                        anchors.fill: parent
                                        enabled: tile.canExpand && !tile.isPending
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: tile.tileExpand()
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ═══════════════════ Volume Slider ═══════════════════

                RowLayout {
                    Layout.fillWidth: true; spacing: 8

                    Components.Icon {
                        source: AudioService.muted ? "../icons/volume-mute.svg" : "../icons/volume-high.svg"
                        color: Theme.fg4
                        Layout.preferredWidth: 16; Layout.alignment: Qt.AlignHCenter
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3

                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * Math.min(1.0, AudioService.volume)
                            radius: parent.radius; color: Theme.greenBright
                            Behavior on width {
                                Components.Anim {
                                    duration: Theme.animMicro
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                        }

                        Rectangle {
                            width: 12; height: 12; radius: 6; color: Theme.fg
                            y: (parent.height - height) / 2
                            x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1.0, AudioService.volume) - width / 2))
                            scale: volSliderMouse.pressed ? 1.2 : (volSliderMouse.containsMouse ? 1.1 : 1.0)
                            Behavior on scale {
                                Components.Anim {
                                    duration: Theme.animMicro
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                            Behavior on x {
                                SpringAnimation { spring: 4; damping: 0.4 }
                            }
                        }

                        Components.HoverLayer {
                            id: volSliderMouse
                            hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                            onPressed: { AudioService.suppressOsd = true; }
                            onReleased: { Qt.callLater(() => { AudioService.suppressOsd = false; }); }
                            onClicked: (mouse) => { AudioService.setVolume(mouse.x / parent.width); }
                            onPositionChanged: (mouse) => { if (pressed) AudioService.setVolume(mouse.x / parent.width); }
                        }
                    }

                    Text {
                        text: Math.round(AudioService.volume * 100) + "%"
                        color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.preferredWidth: qsPop.metricLabelWidth; horizontalAlignment: Text.AlignRight
                    }
                }

                // ═══════════════════ Brightness Slider ═══════════════════

                RowLayout {
                    visible: BrightnessService.hasBacklight
                    Layout.fillWidth: true; spacing: 8

                    Components.Icon {
                        source: BrightnessService.brightnessPercent < 25 ? "../icons/brightness-low.svg" : (BrightnessService.brightnessPercent < 70 ? "../icons/brightness-medium.svg" : "../icons/brightness-high.svg")
                        color: Theme.fg4
                        Layout.preferredWidth: 16; Layout.alignment: Qt.AlignHCenter
                    }

                    Rectangle {
                        Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3

                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * BrightnessService.brightnessFraction
                            radius: parent.radius; color: Theme.yellowBright
                            Behavior on width {
                                Components.Anim {
                                    duration: Theme.animMicro
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                        }

                        Rectangle {
                            width: 12; height: 12; radius: 6; color: Theme.fg
                            y: (parent.height - height) / 2
                            x: Math.max(0, Math.min(parent.width - width, parent.width * BrightnessService.brightnessFraction - width / 2))
                            scale: brightSliderMouse.pressed ? 1.2 : (brightSliderMouse.containsMouse ? 1.1 : 1.0)
                            Behavior on scale {
                                Components.Anim {
                                    duration: Theme.animMicro
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                            Behavior on x {
                                SpringAnimation { spring: 4; damping: 0.4 }
                            }
                        }

                        Components.HoverLayer {
                            id: brightSliderMouse
                            hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                            onClicked: (mouse) => { BrightnessService.setBrightnessFraction(mouse.x / parent.width); }
                            onPositionChanged: (mouse) => {
                                if (pressed)
                                    BrightnessService.setBrightnessFraction(mouse.x / parent.width);
                            }
                        }
                    }

                    Text {
                        text: BrightnessService.brightnessAvailable ? BrightnessService.brightnessPercent + "%" : ""
                        color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.preferredWidth: qsPop.metricLabelWidth; horizontalAlignment: Text.AlignRight
                    }
                }

                // ═══════════════════ Battery Status ═══════════════════

                RowLayout {
                    visible: qsPop.batPresent
                    Layout.fillWidth: true; spacing: 8

                    Components.Icon {
                        source: qsPop.batIcon()
                        color: {
                            if (qsPop.batCharging) return Theme.greenBright;
                            if (qsPop.batPct < 15) return Theme.redBright;
                            if (qsPop.batPct < 30) return Theme.yellowBright;
                            return Theme.fg;
                        }
                    }

                    Text {
                        text: Math.round(qsPop.batPct) + "%"
                        color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall
                        font.bold: true
                    }

                    Text {
                        text: qsPop.batCharging ? "Charging" : "On Battery"
                        color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ═══════════════════ Settings Footer ═══════════════════

                Rectangle {
                    Layout.fillWidth: true; height: Theme.listItemHeight
                    radius: Theme.hoverRadius; color: "transparent"

                    Components.HoverLayer {
                        id: settingsArea
                        hoverOpacity: 0.4; pressedOpacity: 0.7; pressedScale: 0.98
                        color: Theme.bg2
                        onClicked: qsPop.settingsRequested()

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: Theme.listItemPadding
                            spacing: 8

                            Components.Icon {
                                source: "../icons/adjustments.svg"
                                color: settingsArea.containsMouse ? Theme.fg : Theme.fg4
                                Behavior on color { Components.CAnim { duration: Theme.animHover } }
                            }
                            Text {
                                text: "All Settings"
                                color: settingsArea.containsMouse ? Theme.fg : Theme.fg2
                                font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                                Behavior on color { Components.CAnim { duration: Theme.animHover } }
                            }
                            Text {
                                text: ">"
                                color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: 10
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
