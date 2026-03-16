import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PanelWindow {
    id: btPop
    property bool active: false; signal close()
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:bluetooth"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property bool powered: false
    property string connectedName: ""
    property string connectedMac: ""
    property string connectedBattery: ""
    property string connectError: ""

    ListModel { id: pairedModel }
    ListModel { id: discoveredModel }

    // "list" → browsing | "connecting" → in progress
    property string popupState: "list"
    property string targetDevice: ""

    onActiveChanged: {
        if (active) { resetState(); refresh(); startScan(); }
    }

    function resetState() {
        popupState = "list";
        targetDevice = "";
        connectError = "";
    }

    function refresh() {
        pairedModel.clear();
        discoveredModel.clear();
        connectedName = "";
        connectedMac = "";
        connectedBattery = "";
        showProc.running = true;
    }

    function startScan() { scanProc.running = true; }

    // ── Parse "Device AA:BB:CC:DD:EE:FF Name" lines ──
    function parseDevice(line) {
        let m = line.match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$/);
        if (m) return { mac: m[1], name: m[2] };
        return null;
    }

    // ── Processes ───────────────────────────────────────────

    // Check adapter power
    Process {
        id: showProc; command: ["bluetoothctl", "show"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let t = line.trim();
            if (t.startsWith("Powered:")) btPop.powered = t.indexOf("yes") >= 0;
        } }
        onRunningChanged: { if (!running) infoProc.running = true; }
    }

    // Check connected device info
    Process {
        id: infoProc; command: ["bluetoothctl", "info"]; running: false
        property bool _found: false
        stdout: SplitParser { onRead: (line) => {
            let t = line.trim();
            if (t.startsWith("Device ")) {
                let m = t.match(/^Device\s+([0-9A-Fa-f:]{17})/);
                if (m) { btPop.connectedMac = m[1]; infoProc._found = true; }
            }
            if (t.startsWith("Name:")) btPop.connectedName = t.substring(5).trim();
            if (t.startsWith("Battery Percentage:")) {
                let bm = t.match(/0x([0-9a-fA-F]+)\s*\((\d+)\)/);
                if (bm) btPop.connectedBattery = bm[2] + "%";
            }
        } }
        onRunningChanged: {
            if (!running) {
                if (!_found) { btPop.connectedName = ""; btPop.connectedMac = ""; btPop.connectedBattery = ""; }
                _found = false;
                pairedProc.running = true;
            }
        }
    }

    // List paired devices
    Process {
        id: pairedProc; command: ["bluetoothctl", "devices", "Paired"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let d = btPop.parseDevice(line.trim());
            if (d && d.mac !== btPop.connectedMac) {
                pairedModel.append({ mac: d.mac, name: d.name, paired: true });
            }
        } }
        onRunningChanged: { if (!running) discoveredProc.running = true; }
    }

    // List all known devices (discovered minus paired = discovered-only)
    Process {
        id: discoveredProc; command: ["bluetoothctl", "devices"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let d = btPop.parseDevice(line.trim());
            if (!d || d.mac === btPop.connectedMac) return;
            // Skip if already in paired list
            for (let i = 0; i < pairedModel.count; i++)
                if (pairedModel.get(i).mac === d.mac) return;
            discoveredModel.append({ mac: d.mac, name: d.name, paired: false });
        } }
    }

    // Scan for new devices (fire-and-forget, then refresh)
    Process {
        id: scanProc; command: ["bluetoothctl", "--timeout", "8", "scan", "on"]; running: false
        onRunningChanged: {
            if (!running) { pairedModel.clear(); discoveredModel.clear(); pairedProc.running = true; }
        }
    }

    // Connect to device
    Process {
        id: connectProc; running: false
        onExited: (code, status) => {
            if (code === 0) { btPop.resetState(); btPop.refresh(); }
            else { btPop.connectError = "Connection failed (exit " + code + ")"; btPop.popupState = "list"; }
        }
    }

    // Disconnect
    Process {
        id: disconnectProc; command: ["bluetoothctl", "disconnect"]; running: false
        onRunningChanged: { if (!running) { btPop.refresh(); } }
    }

    // Power toggle
    Process { id: powerProc; running: false; onRunningChanged: { if (!running) showProc.running = true; } }



    // ── Backdrop ────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: btPop.close()
        MouseArea { anchors.fill: parent; onClicked: btPop.close() }
    }

    // ── Popup card ──────────────────────────────────────────
    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth; height: btCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: btPop.active ? 1 : 0
        scale: btPop.active ? 1.0 : 0.92
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: btCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 8

            // ── Header ──────────────────────────────────────
            RowLayout { Layout.fillWidth: true
                Text {
                    text: btPop.popupState === "connecting" ? "󰂯  Connecting…" : "󰂯  Bluetooth"
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true
                }
                Text {
                    visible: btPop.popupState === "list"
                    text: scanProc.running ? "Scanning…" : "Scan"
                    color: scanBtnA.containsMouse ? Theme.blueBright : Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    MouseArea { id: scanBtnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { if (!scanProc.running) btPop.startScan(); } }
                }
            }

            // ── Error banner ────────────────────────────────
            Text { visible: btPop.connectError !== ""
                text: btPop.connectError; color: Theme.redBright
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap; Layout.fillWidth: true }

            // ── Power toggle ────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 30; radius: 6
                color: powerArea.containsMouse ? Theme.bg2 : "transparent"

                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                    Text { text: "Bluetooth"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
                    Rectangle {
                        width: 32; height: 16; radius: 8
                        color: btPop.powered ? Theme.blueBright : Theme.bg3
                        Behavior on color { ColorAnimation { duration: 150 } }
                        Rectangle {
                            width: 12; height: 12; radius: 6; y: 2
                            x: btPop.powered ? parent.width - width - 2 : 2
                            color: Theme.fg
                            Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        }
                    }
                }
                MouseArea { id: powerArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: {
                        powerProc.command = ["bluetoothctl", "power", btPop.powered ? "off" : "on"];
                        powerProc.running = true;
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ══════════════════════════════════════════════════
            // ── LIST STATE ───────────────────────────────────
            // ══════════════════════════════════════════════════

            // ── Bluetooth off message ───────────────────────
            Text {
                visible: btPop.popupState === "list" && !btPop.powered
                text: "Bluetooth is off"; color: Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }

            // ── Connected device ────────────────────────────
            Rectangle {
                visible: btPop.popupState === "list" && btPop.connectedName !== ""
                Layout.fillWidth: true; height: 40; radius: 6
                color: connDevArea.containsMouse ? Theme.bg2 : "transparent"

                RowLayout {
                    anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                    Text { text: "󰥰"; color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
                    ColumnLayout { spacing: 0; Layout.fillWidth: true
                        Text { text: btPop.connectedName; color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                        Text {
                            visible: btPop.connectedBattery !== ""
                            text: "Battery: " + btPop.connectedBattery; color: Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                        }
                    }
                    Rectangle {
                        width: discLabel.implicitWidth + 16; height: 22; radius: 6
                        color: discBtnA.containsMouse ? Theme.redBright : Theme.bg3
                        Text { id: discLabel; anchors.centerIn: parent; text: "Disconnect"
                            color: discBtnA.containsMouse ? Theme.bg : Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                        MouseArea { id: discBtnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: disconnectProc.running = true }
                    }
                }
                MouseArea { id: connDevArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; z: -1 }
            }

            // ── Separator if connected ──────────────────────
            Rectangle {
                visible: btPop.popupState === "list" && btPop.connectedName !== "" && (pairedModel.count > 0 || discoveredModel.count > 0)
                Layout.fillWidth: true; height: 1; color: Theme.bg3
            }

            // ── Device lists ────────────────────────────────
            Flickable {
                visible: btPop.popupState === "list" && btPop.powered
                Layout.fillWidth: true; Layout.preferredHeight: 170; Layout.maximumHeight: 170
                contentHeight: devCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: devCol; width: parent.width; spacing: 4

                    // ── Paired header ──
                    Text {
                        visible: pairedModel.count > 0
                        text: "Paired"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                        topPadding: 2; bottomPadding: 2; leftPadding: 8
                    }

                    Repeater {
                        model: pairedModel
                        Rectangle {
                            id: pItem; required property string mac; required property string name
                            width: devCol.width; height: 30; radius: 6
                            color: piArea.containsMouse ? Theme.bg2 : "transparent"

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                                Text { text: "󰂯"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
                                Text { text: pItem.name; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    Layout.fillWidth: true; elide: Text.ElideRight }
                                Rectangle {
                                    width: pConnLabel.implicitWidth + 16; height: 22; radius: 6
                                    color: pConnA.containsMouse ? Theme.blueBright : Theme.bg3
                                    Text { id: pConnLabel; anchors.centerIn: parent; text: "Connect"
                                        color: pConnA.containsMouse ? Theme.bg : Theme.fg
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                    MouseArea { id: pConnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                        onClicked: {
                                            btPop.popupState = "connecting";
                                            btPop.targetDevice = pItem.name;
                                            connectProc.command = ["bluetoothctl", "connect", pItem.mac];
                                            connectProc.running = true;
                                        }
                                    }
                                }
                            }
                            MouseArea { id: piArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; z: -1 }
                        }
                    }

                    // ── Discovered header ──
                    Text {
                        visible: discoveredModel.count > 0
                        text: "Discovered"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                        topPadding: 6; bottomPadding: 2; leftPadding: 8
                    }

                    Repeater {
                        model: discoveredModel
                        Rectangle {
                            id: dItem; required property string mac; required property string name
                            width: devCol.width; height: 30; radius: 6
                            color: diArea.containsMouse ? Theme.bg2 : "transparent"

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                                Text { text: "󰂯"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
                                Text { text: dItem.name; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    Layout.fillWidth: true; elide: Text.ElideRight }
                                Rectangle {
                                    width: dConnLabel.implicitWidth + 16; height: 22; radius: 6
                                    color: dConnA.containsMouse ? Theme.blueBright : Theme.bg3
                                    Text { id: dConnLabel; anchors.centerIn: parent; text: "Connect"
                                        color: dConnA.containsMouse ? Theme.bg : Theme.fg
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                    MouseArea { id: dConnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                        onClicked: {
                                            btPop.popupState = "connecting";
                                            btPop.targetDevice = dItem.name;
                                            connectProc.command = ["bluetoothctl", "connect", dItem.mac];
                                            connectProc.running = true;
                                        }
                                    }
                                }
                            }
                            MouseArea { id: diArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; z: -1 }
                        }
                    }
                }
            }

            Text { visible: btPop.popupState === "list" && btPop.powered && pairedModel.count === 0 && discoveredModel.count === 0 && !scanProc.running
                text: "No devices found"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }

            Text { visible: btPop.popupState === "list" && btPop.powered && pairedModel.count === 0 && discoveredModel.count === 0 && scanProc.running
                text: "Scanning…"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }



            // ══════════════════════════════════════════════════
            // ── CONNECTING STATE ─────────────────────────────
            // ══════════════════════════════════════════════════
            ColumnLayout {
                visible: btPop.popupState === "connecting"
                Layout.fillWidth: true; spacing: 8; Layout.alignment: Qt.AlignHCenter

                Text { text: "Connecting to " + btPop.targetDevice + "…"; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.alignment: Qt.AlignHCenter }

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
