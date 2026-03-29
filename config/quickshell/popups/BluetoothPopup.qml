import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components" as Components

FocusScope {
    id: btPop
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: btContentLoader.item
    readonly property Item focusTarget: btPop
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
    WlrLayershell.namespace: "quickshell:bluetooth"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: btPop.close()
        MouseArea { anchors.fill: parent; onClicked: btPop.close() }
    }
    */

    property bool powered: false
    property bool scanning: false
    property string connectedName: ""
    property string connectedMac: ""
    property int connectedBattery: -1
    property string popupState: "list"
    property string targetName: ""
    property string connectError: ""
    property bool deviceListLoading: popupState === "list"
        && pairedModel.count === 0
        && discoveredModel.count === 0
        && (showProc.running || connInfoProc.running || pairedProc.running || allDevicesProc.running || btPop.scanning)

    ListModel { id: pairedModel }
    ListModel { id: discoveredModel }

    function preparePanelForOpen() {
        let item = btContentLoader.item;
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
                btOpenAnim.start();
            resetState(); refresh();
        } else if (!closing) {
            if (btContentLoader.item) {
                closing = true;
                btCloseAnim.start();
            } else {
                closing = false;
            }
        }
    }

    SequentialAnimation {
        id: btOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: btContentLoader.item
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            Components.Anim {
                target: btContentLoader.item
                property: "scale"
                to: 1.0
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
        }
    }
    SequentialAnimation {
        id: btCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: btContentLoader.item
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: btContentLoader.item
                property: "scale"
                to: 0.92
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { btPop.closing = false; } }
    }

    function resetState() {
        popupState = "list"; targetName = ""; connectError = "";
    }

    function refresh() {
        connectedName = ""; connectedMac = ""; connectedBattery = -1;
        pairedModel.clear(); discoveredModel.clear();
        showProc.running = true;
    }

    function startScan() {
        scanning = true;
        scanProc.running = true;
    }

    function connectDevice(mac, name) {
        popupState = "connecting"; targetName = name; connectError = "";
        connectProc.command = ["bluetoothctl", "connect", mac];
        connectProc.running = true;
    }

    function disconnectDevice() {
        disconnectProc.running = true;
    }

    function togglePower() {
        powerProc.command = ["bluetoothctl", "power", powered ? "off" : "on"];
        powerProc.running = true;
    }

    function isMacAddress(name) {
        return /^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$/.test(name);
    }

    // ── Processes ─────────────────────────────────────────────
    Process {
        id: showProc
        command: ["bluetoothctl", "show"]
        running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { showProc.buf += line + "\n"; } }
        onExited: {
            btPop.powered = showProc.buf.indexOf("Powered: yes") >= 0;
            showProc.buf = "";
            if (btPop.powered) connInfoProc.running = true;
        }
    }

    Process {
        id: connInfoProc
        command: ["bash", "-c",
            "dev=$(bluetoothctl devices Connected 2>/dev/null | head -1); " +
            "[ -z \"$dev\" ] && exit 0; " +
            "mac=$(echo \"$dev\" | awk '{print $2}'); " +
            "name=$(echo \"$dev\" | sed 's/^Device [^ ]* //'); " +
            "echo \"CONN|$mac|$name\"; " +
            "batt=$(bluetoothctl info \"$mac\" 2>/dev/null | awk -F'[()]' '/Battery Percentage/{print $2}'); " +
            "[ -n \"$batt\" ] && echo \"BATT|$batt\""
        ]
        running: false
        stdout: SplitParser { onRead: (line) => {
            if (line.startsWith("CONN|")) {
                let parts = line.substring(5).split("|");
                if (parts.length >= 2) {
                    btPop.connectedMac = parts[0];
                    btPop.connectedName = parts.slice(1).join("|");
                }
            } else if (line.startsWith("BATT|")) {
                btPop.connectedBattery = parseInt(line.substring(5)) || -1;
            }
        } }
        onExited: { pairedProc.running = true; }
    }

    Process {
        id: pairedProc
        command: ["bluetoothctl", "devices", "Paired"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let m = line.match(/^Device\s+(\S+)\s+(.+)$/);
            if (!m) return;
            let mac = m[1], name = m[2];
            if (btPop.isMacAddress(name)) return;
            if (mac === btPop.connectedMac) return;
            pairedModel.append({ mac: mac, name: name });
        } }
        onExited: { allDevicesProc.running = true; }
    }

    Process {
        id: allDevicesProc
        command: ["bluetoothctl", "devices"]
        running: false
        stdout: SplitParser { onRead: (line) => {
            let m = line.match(/^Device\s+(\S+)\s+(.+)$/);
            if (!m) return;
            let mac = m[1], name = m[2];
            if (btPop.isMacAddress(name)) return;
            if (mac === btPop.connectedMac) return;
            for (let i = 0; i < pairedModel.count; i++)
                if (pairedModel.get(i).mac === mac) return;
            discoveredModel.append({ mac: mac, name: name });
        } }
        onExited: { btPop.startScan(); }
    }

    Process {
        id: scanProc
        command: ["bluetoothctl", "--timeout", "8", "scan", "on"]
        running: false
        onExited: { btPop.scanning = false; }
    }

    Process {
        id: connectProc; running: false
        onExited: (code, status) => {
            if (code === 0) { btPop.resetState(); btPop.refresh(); }
            else { btPop.connectError = "Connection failed"; btPop.popupState = "error"; errorTimer.restart(); }
        }
    }

    Process {
        id: disconnectProc
        command: ["bluetoothctl", "disconnect"]
        running: false
        onExited: { btPop.resetState(); btPop.refresh(); }
    }

    Process { id: powerProc; running: false; onExited: { btPop.refresh(); } }

    Timer {
        id: errorTimer; interval: 2000
        onTriggered: { btPop.connectError = ""; btPop.popupState = "list"; }
    }

    // ── Backdrop ──────────────────────────────────────────────
    Keys.onEscapePressed: btPop.close()

    Loader {
        id: btContentLoader
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth
        height: item ? item.implicitHeight : 0
        active: btPop.contentLoaded || btPop.active || btPop.closing
        asynchronous: true
        sourceComponent: btPanelComponent

        onLoaded: {
            item.opacity = 0;
            item.scale = 0.92;
            if (btPop.active)
                btOpenAnim.start();
        }
    }

    Component {
        id: btPanelComponent

        // ── Popup card ────────────────────────────────────────────
        Rectangle {
            id: btPanel
            anchors.fill: parent
            implicitHeight: btCol.implicitHeight + Theme.popupPadding * 2
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
                id: btCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 8

            // ── Header ──────────────────────────────────────
            RowLayout { Layout.fillWidth: true
                Text {
                    text: btPop.popupState === "connecting" ? "󰂯  Connecting…" : "󰂯  Bluetooth"
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true
                }
                Rectangle {
                    visible: btPop.popupState === "list" && btPop.powered
                    Layout.preferredWidth: scanLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: scanA
                        color: Theme.bg2
                        hoverOpacity: 0.6
                        pressedOpacity: 0.9
                        pressedScale: 0.98
                        onClicked: { if (!btPop.scanning) btPop.startScan(); }

                        Text { id: scanLabel; anchors.centerIn: parent
                            text: btPop.scanning ? "Scanning…" : "Scan"
                            color: scanA.containsMouse ? Theme.blueBright : Theme.fg4
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

            // ── Power toggle ────────────────────────────────
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text { text: "Power"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
                Components.ToggleSwitch {
                    checked: btPop.powered
                    onToggled: btPop.togglePower()
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── Powered off empty state ─────────────────────
            Item {
                visible: !btPop.powered && btPop.popupState === "list" && !btPop.deviceListLoading
                Layout.fillWidth: true; implicitHeight: 40
                Text { anchors.centerIn: parent; text: "Bluetooth is off"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            }

            // ── Connected device ────────────────────────────
            Item {
                visible: btPop.popupState === "list" && btPop.powered && btPop.connectedName !== ""
                Layout.fillWidth: true; implicitHeight: 30

                Rectangle { id: connAccent; width: 3; height: parent.height; radius: 1.5; color: Theme.greenBright
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }

                Text {
                    anchors.left: connAccent.right; anchors.leftMargin: 8
                    anchors.right: connBattText.visible ? connBattText.left : connDcBtn.left
                    anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: btPop.connectedName; color: Theme.greenBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }

                Text {
                    id: connBattText; visible: btPop.connectedBattery >= 0
                    anchors.right: connDcBtn.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: btPop.connectedBattery + "%"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                }

                Rectangle {
                    id: connDcBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: connDcLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: connDcA
                        color: Theme.bg2
                        hoverOpacity: 0.6
                        pressedOpacity: 0.9
                        pressedScale: 0.98
                        onClicked: btPop.disconnectDevice()

                        Text { id: connDcLabel; anchors.centerIn: parent; text: "Disconnect"
                            color: connDcA.containsMouse ? Theme.redBright : Theme.fg4
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

            // ── Error message ───────────────────────────────
            Item {
                Layout.fillWidth: true; visible: btPop.connectError !== ""
                implicitHeight: errorText.implicitHeight
                Text { id: errorText; width: parent.width
                    text: btPop.connectError; color: Theme.redBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    opacity: btPop.connectError !== "" ? 1 : 0
                    y: btPop.connectError !== "" ? 0 : 6
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

            // ── Device list ─────────────────────────────────
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 170; Layout.maximumHeight: 170
                visible: btPop.popupState === "list" && (btPop.powered || btPop.deviceListLoading)
                opacity: btPop.popupState === "list" && (btPop.powered || btPop.deviceListLoading) ? 1 : 0
                clip: true
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }

                Components.WheelFlickable {
                    anchors.fill: parent
                    opacity: btPop.deviceListLoading ? 0 : 1
                    enabled: opacity > 0.01
                    Behavior on opacity {
                        Components.Anim {
                            duration: Theme.animContentSwap
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    contentHeight: devCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: devCol; width: parent.width; spacing: 4

                        // ── PAIRED header ──
                        Text {
                            visible: pairedModel.count > 0
                            text: "PAIRED"; color: Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
                            topPadding: 4; bottomPadding: 2; leftPadding: Theme.listItemPadding
                        }

                        // ── PAIRED devices ──
                        Repeater {
                            model: pairedModel
                            Rectangle {
                                id: pItem; required property string mac; required property string name; required property int index
                                width: devCol.width; height: 30; radius: Theme.hoverRadius; color: "transparent"

                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                    opacity: pArea.pressed ? 0.9 : (pArea.containsMouse ? 0.6 : 0)
                                    Behavior on opacity {
                                        Components.Anim {
                                            duration: Theme.animHover
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.animCurveStandard
                                        }
                                    }
                                }
                                scale: pArea.pressed ? 0.98 : 1.0
                                Behavior on scale {
                                    Components.Anim {
                                        duration: Theme.animMicro
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                                transformOrigin: Item.Center

                                Text {
                                    id: pIcon; text: "󰂯"
                                    anchors.left: parent.left; anchors.leftMargin: Theme.listItemPadding
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                                }
                                Text {
                                    anchors.left: pIcon.right; anchors.leftMargin: 6
                                    anchors.right: pConnect.left; anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pItem.name; color: Theme.fg
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: pConnect
                                    anchors.right: parent.right; anchors.rightMargin: Theme.listItemPadding
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Connect"; color: pArea.containsMouse ? Theme.blueBright : Theme.fg4
                                    Behavior on color {
                                        Components.CAnim {
                                            duration: Theme.animHover
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.animCurveStandard
                                        }
                                    }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                }

                                Components.HoverLayer { id: pArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                    onClicked: btPop.connectDevice(pItem.mac, pItem.name) }
                            }
                        }

                        // ── DISCOVERED header ──
                        Text {
                            visible: discoveredModel.count > 0
                            text: "DISCOVERED"; color: Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1; font.bold: true
                            topPadding: 4; bottomPadding: 2; leftPadding: Theme.listItemPadding
                        }

                        // ── DISCOVERED devices ──
                        Repeater {
                            model: discoveredModel
                            Rectangle {
                                id: dItem; required property string mac; required property string name; required property int index
                                width: devCol.width; height: 30; radius: Theme.hoverRadius; color: "transparent"

                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                    opacity: dArea.pressed ? 0.9 : (dArea.containsMouse ? 0.6 : 0)
                                    Behavior on opacity {
                                        Components.Anim {
                                            duration: Theme.animHover
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.animCurveStandard
                                        }
                                    }
                                }
                                scale: dArea.pressed ? 0.98 : 1.0
                                Behavior on scale {
                                    Components.Anim {
                                        duration: Theme.animMicro
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                                transformOrigin: Item.Center

                                Text {
                                    id: dIcon; text: "󰂯"
                                    anchors.left: parent.left; anchors.leftMargin: Theme.listItemPadding
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                                }
                                Text {
                                    anchors.left: dIcon.right; anchors.leftMargin: 6
                                    anchors.right: dConnect.left; anchors.rightMargin: 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: dItem.name; color: Theme.fg
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: dConnect
                                    anchors.right: parent.right; anchors.rightMargin: Theme.listItemPadding
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Connect"; color: dArea.containsMouse ? Theme.blueBright : Theme.fg4
                                    Behavior on color {
                                        Components.CAnim {
                                            duration: Theme.animHover
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Theme.animCurveStandard
                                        }
                                    }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                }

                                Components.HoverLayer { id: dArea; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                                    onClicked: btPop.connectDevice(dItem.mac, dItem.name) }
                            }
                        }

                    }
                }

                Column {
                    anchors.fill: parent
                    anchors.topMargin: 4
                    spacing: 4
                    opacity: btPop.deviceListLoading ? 1 : 0
                    visible: opacity > 0
                    z: 1
                    Behavior on opacity {
                        Components.Anim {
                            duration: Theme.animContentSwap
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }

                    Item {
                        width: parent.width
                        height: 14
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.listItemPadding
                            anchors.verticalCenter: parent.verticalCenter
                            width: 46; height: 8; radius: 4; color: Theme.bg3
                        }
                    }

                    Repeater {
                        model: ListModel {
                            ListElement { skelWidth: 110 }
                            ListElement { skelWidth: 140 }
                        }
                        delegate: Item {
                            required property int skelWidth
                            required property int index
                            width: parent.width
                            height: 30

                            RowLayout {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.listItemPadding
                                anchors.rightMargin: Theme.listItemPadding
                                spacing: 8

                                Rectangle { width: 14; height: 14; radius: 7; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Item { Layout.fillWidth: true }
                                Rectangle { width: 44; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                            }

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: index * 120 }
                                Components.Anim { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                Components.Anim { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 14
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.listItemPadding
                            anchors.verticalCenter: parent.verticalCenter
                            width: 72; height: 8; radius: 4; color: Theme.bg3
                        }
                    }

                    Repeater {
                        model: ListModel {
                            ListElement { skelWidth: 95 }
                            ListElement { skelWidth: 125 }
                        }
                        delegate: Item {
                            required property int skelWidth
                            required property int index
                            width: parent.width
                            height: 30

                            RowLayout {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Theme.listItemPadding
                                anchors.rightMargin: Theme.listItemPadding
                                spacing: 8

                                Rectangle { width: 14; height: 14; radius: 7; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                Item { Layout.fillWidth: true }
                                Rectangle { width: 44; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                            }

                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: (index + 2) * 120 }
                                Components.Anim { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                                Components.Anim { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                            }
                        }
                    }
                }
            }

            // ── Scanning indicator ──────────────────────────
            Item {
                visible: btPop.popupState === "list" && btPop.powered && !btPop.deviceListLoading
                    && btPop.scanning && pairedModel.count === 0 && discoveredModel.count === 0
                Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
                implicitHeight: scanningRow.implicitHeight
                RowLayout {
                    id: scanningRow; anchors.centerIn: parent; spacing: 6
                    Text { text: "󰂯"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            NumberAnimation { from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                            NumberAnimation { from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutQuad }
                        }
                    }
                    Text { text: "Scanning…"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }

            // ── CONNECTING ──────────────────────────────────
            ColumnLayout {
                visible: btPop.popupState === "connecting"
                opacity: btPop.popupState === "connecting" ? 1 : 0
                Behavior on opacity {
                    Components.Anim {
                        duration: Theme.animContentSwap
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }
                Layout.fillWidth: true; spacing: 8; Layout.alignment: Qt.AlignHCenter

                Text { text: "Connecting to " + btPop.targetName + "…"; color: Theme.fg
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
            }
        }
    }
}
