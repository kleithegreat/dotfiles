import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components" as Components

PanelWindow {
    id: btPop
    property bool active: false; signal close()
    property bool closing: false
    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:bluetooth"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property bool powered: false
    property bool scanning: false
    property string connectedName: ""
    property string connectedMac: ""
    property int connectedBattery: -1
    property string popupState: "list"
    property string targetName: ""
    property string connectError: ""

    ListModel { id: pairedModel }
    ListModel { id: discoveredModel }

    onActiveChanged: {
        if (active) {
            btPanel.opacity = 0; btPanel.scale = 0.92;
            btOpenAnim.start();
            resetState(); refresh();
        } else if (!closing) {
            closing = true; btCloseAnim.start();
        }
    }

    SequentialAnimation {
        id: btOpenAnim
        ParallelAnimation {
            NumberAnimation { target: btPanel; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: btPanel; property: "scale"; to: 1.0; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: btCloseAnim
        ParallelAnimation {
            NumberAnimation { target: btPanel; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
            NumberAnimation { target: btPanel; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
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
    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: btPop.close()
        MouseArea { anchors.fill: parent; onClicked: btPop.close() }
    }

    // ── Popup card ────────────────────────────────────────────
    Rectangle {
        id: btPanel
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth; height: btCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: 0.92
        transformOrigin: Item.TopRight
        Behavior on height { NumberAnimation { duration: Theme.animHeightResize; easing.type: Easing.OutCubic } }
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
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: scanA.pressed ? 0.9 : (scanA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: scanA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: scanLabel; anchors.centerIn: parent
                        text: btPop.scanning ? "Scanning…" : "Scan"
                        color: scanA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: scanA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { if (!btPop.scanning) btPop.startScan(); } }
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
                visible: !btPop.powered && btPop.popupState === "list"
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
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: connDcA.pressed ? 0.9 : (connDcA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: connDcA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: connDcLabel; anchors.centerIn: parent; text: "Disconnect"
                        color: connDcA.containsMouse ? Theme.redBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: connDcA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: btPop.disconnectDevice() }
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
                    Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                }
            }

            // ── Device list ─────────────────────────────────
            Item {
                Layout.fillWidth: true; Layout.preferredHeight: 170; Layout.maximumHeight: 170
                visible: btPop.popupState === "list" && btPop.powered
                opacity: btPop.popupState === "list" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }

                Flickable {
                    anchors.fill: parent
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
                                    Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                                }
                                scale: pArea.pressed ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
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
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea { id: pArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
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
                                    Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                                }
                                scale: dArea.pressed ? 0.98 : 1.0
                                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
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
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                }

                                MouseArea { id: dArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: btPop.connectDevice(dItem.mac, dItem.name) }
                            }
                        }

                        // ── Skeleton loading rows ──
                        Column {
                            visible: btPop.scanning && btPop.powered && btPop.popupState === "list"
                            width: parent.width; spacing: 0

                            Repeater {
                                model: ListModel {
                                    ListElement { skelWidth: 110 }
                                    ListElement { skelWidth: 140 }
                                    ListElement { skelWidth: 95 }
                                    ListElement { skelWidth: 125 }
                                }
                                delegate: Item {
                                    required property int skelWidth
                                    required property int index
                                    width: parent.width; height: 30
                                    RowLayout {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left; anchors.right: parent.right
                                        anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: Theme.listItemPadding
                                        spacing: 8

                                        Rectangle { width: 14; height: 14; radius: 7; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                        Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                                        Item { Layout.fillWidth: true }
                                        Rectangle { width: 44; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
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
                }
            }

            // ── Scanning indicator ──────────────────────────
            Item {
                visible: btPop.popupState === "list" && btPop.powered && pairedModel.count === 0 && discoveredModel.count === 0
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
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
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
