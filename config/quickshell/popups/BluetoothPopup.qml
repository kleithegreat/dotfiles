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
    property string connectedName: ""
    property string connectedMac: ""
    property string connectedBattery: ""
    property string connectError: ""

    ListModel { id: pairedModel }
    ListModel { id: discoveredModel }

    property string popupState: "list"
    property string targetDevice: ""

    onActiveChanged: {
        if (active) {
            btPanel.opacity = 0; btPanel.scale = 0.92;
            btOpenAnim.start();
            resetState(); refresh(); startScan();
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

    function resetState() { popupState = "list"; targetDevice = ""; connectError = ""; }

    function refresh() {
        pairedModel.clear(); discoveredModel.clear();
        connectedName = ""; connectedMac = ""; connectedBattery = "";
        showProc.running = true;
    }

    function startScan() { scanProc.running = true; }

    function parseDevice(line) {
        let m = line.match(/^Device\s+([0-9A-Fa-f:]{17})\s+(.+)$/);
        if (m) return { mac: m[1], name: m[2] };
        return null;
    }

    // ── Processes ───────────────────────────────────────────
    Process {
        id: showProc; command: ["bluetoothctl", "show"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let t = line.trim();
            if (t.startsWith("Powered:")) btPop.powered = t.indexOf("yes") >= 0;
        } }
        onRunningChanged: { if (!running) infoProc.running = true; }
    }

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

    Process {
        id: pairedProc; command: ["bluetoothctl", "devices", "Paired"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let d = btPop.parseDevice(line.trim());
            if (d && d.mac !== btPop.connectedMac)
                pairedModel.append({ mac: d.mac, name: d.name, paired: true });
        } }
        onRunningChanged: { if (!running) discoveredProc.running = true; }
    }

    Process {
        id: discoveredProc; command: ["bluetoothctl", "devices"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let d = btPop.parseDevice(line.trim());
            if (!d || d.mac === btPop.connectedMac) return;
            for (let i = 0; i < pairedModel.count; i++)
                if (pairedModel.get(i).mac === d.mac) return;
            discoveredModel.append({ mac: d.mac, name: d.name, paired: false });
        } }
    }

    Process {
        id: scanProc; command: ["bluetoothctl", "--timeout", "8", "scan", "on"]; running: false
        onRunningChanged: {
            if (!running) { pairedModel.clear(); discoveredModel.clear(); pairedProc.running = true; }
        }
    }

    Process {
        id: connectProc; running: false
        onExited: (code, status) => {
            if (code === 0) { btPop.resetState(); btPop.refresh(); }
            else { btPop.connectError = "Connection failed (exit " + code + ")"; btPop.popupState = "list"; }
        }
    }

    Process {
        id: disconnectProc; command: ["bluetoothctl", "disconnect"]; running: false
        onRunningChanged: { if (!running) { btPop.refresh(); } }
    }

    Process { id: powerProc; running: false; onRunningChanged: { if (!running) showProc.running = true; } }

    // ── Backdrop ────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: btPop.close()
        MouseArea { anchors.fill: parent; onClicked: btPop.close() }
    }

    // ── Popup card ──────────────────────────────────────────
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

            // ── Header ──
            RowLayout { Layout.fillWidth: true
                Text {
                    text: btPop.popupState === "connecting" ? "󰂯  Connecting…" : "󰂯  Bluetooth"
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true
                }
                Rectangle {
                    visible: btPop.popupState === "list"
                    width: scanBtnLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: scanBtnA.pressed ? 0.9 : (scanBtnA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: scanBtnA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: scanBtnLabel; anchors.centerIn: parent
                        text: scanProc.running ? "Scanning…" : "Scan"
                        color: scanBtnA.containsMouse ? Theme.blueBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: scanBtnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { if (!scanProc.running) btPop.startScan(); } }
                }
            }

            // ── Error banner ──
            Item {
                Layout.fillWidth: true; visible: btPop.connectError !== ""
                implicitHeight: btErrorText.implicitHeight
                Text { id: btErrorText; width: parent.width
                    text: btPop.connectError; color: Theme.redBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    opacity: btPop.connectError !== "" ? 1 : 0
                    y: btPop.connectError !== "" ? 0 : 6
                    Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                    Behavior on y { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                }
            }

            // ── Power toggle ──
            RowLayout {
                Layout.fillWidth: true; Layout.preferredHeight: Theme.listItemHeight; spacing: 6
                Layout.leftMargin: Theme.listItemPadding; Layout.rightMargin: Theme.listItemPadding
                Text { text: "Power"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
                Components.ToggleSwitch {
                    checked: btPop.powered
                    onToggled: {
                        powerProc.command = ["bluetoothctl", "power", btPop.powered ? "off" : "on"];
                        powerProc.running = true;
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── Bluetooth off ──
            ColumnLayout {
                visible: btPop.popupState === "list" && !btPop.powered
                Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: 4
                Layout.topMargin: 12; Layout.bottomMargin: 12
                Text { text: "󰂲"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: 24; Layout.alignment: Qt.AlignHCenter }
                Text { text: "Bluetooth is off"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }
            }

            // ── Connected device ──
            Rectangle {
                visible: btPop.popupState === "list" && btPop.connectedName !== ""
                Layout.fillWidth: true; height: Theme.listItemHeight; radius: Theme.hoverRadius
                color: "transparent"
                border.width: 1; border.color: Theme.greenBright
                Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }

                Rectangle {
                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                    opacity: connDevArea.pressed ? 0.9 : (connDevArea.containsMouse ? 0.6 : 0)
                    Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                }
                scale: connDevArea.pressed ? 0.98 : 1.0
                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                transformOrigin: Item.Center

                Text {
                    id: connIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.listItemPadding
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰥰"; color: Theme.greenBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                }

                Rectangle {
                    id: discBtn
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.listItemPadding
                    anchors.verticalCenter: parent.verticalCenter
                    width: discLabel.implicitWidth + Theme.btnPaddingH * 2
                    height: Theme.btnHeight; radius: Theme.btnRadius
                    color: discBtnA.containsMouse ? Theme.redBright : Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    scale: discBtnA.pressed ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: discLabel; anchors.centerIn: parent; text: "Disconnect"
                        color: discBtnA.containsMouse ? Theme.bg : Theme.fg
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: discBtnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: disconnectProc.running = true }
                }

                Column {
                    anchors.left: connIcon.right
                    anchors.leftMargin: 8
                    anchors.right: discBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        width: parent.width
                        text: btPop.connectedName; color: Theme.greenBright
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: btPop.connectedBattery !== ""
                        width: parent.width
                        text: "Battery: " + btPop.connectedBattery; color: Theme.fg4
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                    }
                }

                MouseArea { id: connDevArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; z: -1 }
            }

            Rectangle {
                visible: btPop.popupState === "list" && btPop.connectedName !== "" && (pairedModel.count > 0 || discoveredModel.count > 0)
                Layout.fillWidth: true; height: 1; color: Theme.bg3
            }

            // ── Device lists ──
            Flickable {
                visible: btPop.popupState === "list" && btPop.powered
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(devCol.implicitHeight, 240)
                contentHeight: devCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: devCol; width: parent.width; spacing: 4

                    Text {
                        visible: pairedModel.count > 0
                        text: "PAIRED"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        font.bold: true; font.capitalization: Font.AllUppercase
                        topPadding: 8; bottomPadding: 4; leftPadding: Theme.listItemPadding
                    }

                    Repeater {
                        model: pairedModel
                        Rectangle {
                            id: pItem; required property string mac; required property string name; required property int index
                            width: devCol.width; height: Theme.listItemHeight; radius: Theme.hoverRadius
                            color: "transparent"

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                opacity: piArea.pressed ? 0.9 : (piArea.containsMouse ? 0.6 : 0)
                                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                            }
                            scale: piArea.pressed ? 0.98 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            opacity: 0; y: 8
                            Component.onCompleted: { pItemAnim.delay = index * Theme.animStagger; pItemAnim.start(); }
                            SequentialAnimation {
                                id: pItemAnim; property int delay: 0
                                PauseAnimation { duration: pItemAnim.delay }
                                ParallelAnimation {
                                    NumberAnimation { target: pItem; property: "opacity"; to: 1; duration: Theme.animContentSwap; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: pItem; property: "y"; to: 0; duration: Theme.animContentSwap; easing.type: Easing.OutCubic }
                                }
                            }

                            Text {
                                id: pIcon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.listItemPadding
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰂯"; color: Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                            }

                            Rectangle {
                                id: pConnBtn
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.listItemPadding
                                anchors.verticalCenter: parent.verticalCenter
                                width: pConnLabel.implicitWidth + Theme.btnPaddingH * 2
                                height: Theme.btnHeight; radius: Theme.btnRadius
                                color: pConnA.containsMouse ? Theme.blueBright : Theme.bg3
                                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                scale: pConnA.pressed ? 0.95 : 1.0
                                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                transformOrigin: Item.Center
                                Text { id: pConnLabel; anchors.centerIn: parent; text: "Connect"
                                    color: pConnA.containsMouse ? Theme.bg : Theme.fg
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                                MouseArea { id: pConnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: {
                                        btPop.popupState = "connecting"; btPop.targetDevice = pItem.name;
                                        connectProc.command = ["bluetoothctl", "connect", pItem.mac]; connectProc.running = true;
                                    } }
                            }

                            Text {
                                anchors.left: pIcon.right
                                anchors.leftMargin: 8
                                anchors.right: pConnBtn.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: pItem.name; color: Theme.fg
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                            }

                            MouseArea { id: piArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; z: -1 }
                        }
                    }

                    Text {
                        visible: discoveredModel.count > 0
                        text: "DISCOVERED"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        font.bold: true; font.capitalization: Font.AllUppercase
                        topPadding: 8; bottomPadding: 4; leftPadding: Theme.listItemPadding
                    }

                    Repeater {
                        model: discoveredModel
                        Rectangle {
                            id: dItem; required property string mac; required property string name; required property int index
                            width: devCol.width; height: Theme.listItemHeight; radius: Theme.hoverRadius
                            color: "transparent"

                            Rectangle {
                                anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                opacity: diArea.pressed ? 0.9 : (diArea.containsMouse ? 0.6 : 0)
                                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                            }
                            scale: diArea.pressed ? 0.98 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            opacity: 0; y: 8
                            Component.onCompleted: { dItemAnim.delay = index * Theme.animStagger; dItemAnim.start(); }
                            SequentialAnimation {
                                id: dItemAnim; property int delay: 0
                                PauseAnimation { duration: dItemAnim.delay }
                                ParallelAnimation {
                                    NumberAnimation { target: dItem; property: "opacity"; to: 1; duration: Theme.animContentSwap; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: dItem; property: "y"; to: 0; duration: Theme.animContentSwap; easing.type: Easing.OutCubic }
                                }
                            }

                            Text {
                                id: dIcon
                                anchors.left: parent.left
                                anchors.leftMargin: Theme.listItemPadding
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰂯"; color: Theme.fg4
                                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                            }

                            Rectangle {
                                id: dConnBtn
                                anchors.right: parent.right
                                anchors.rightMargin: Theme.listItemPadding
                                anchors.verticalCenter: parent.verticalCenter
                                width: dConnLabel.implicitWidth + Theme.btnPaddingH * 2
                                height: Theme.btnHeight; radius: Theme.btnRadius
                                color: dConnA.containsMouse ? Theme.blueBright : Theme.bg3
                                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                scale: dConnA.pressed ? 0.95 : 1.0
                                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                transformOrigin: Item.Center
                                Text { id: dConnLabel; anchors.centerIn: parent; text: "Connect"
                                    color: dConnA.containsMouse ? Theme.bg : Theme.fg
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                                MouseArea { id: dConnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: {
                                        btPop.popupState = "connecting"; btPop.targetDevice = dItem.name;
                                        connectProc.command = ["bluetoothctl", "connect", dItem.mac]; connectProc.running = true;
                                    } }
                            }

                            Text {
                                anchors.left: dIcon.right
                                anchors.leftMargin: 8
                                anchors.right: dConnBtn.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: dItem.name; color: Theme.fg3
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                            }

                            MouseArea { id: diArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; z: -1 }
                        }
                    }
                }
            }

            Text { visible: btPop.popupState === "list" && btPop.powered && pairedModel.count === 0 && discoveredModel.count === 0 && !scanProc.running
                text: "No devices found"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }

            Item {
                visible: btPop.popupState === "list" && btPop.powered && pairedModel.count === 0 && discoveredModel.count === 0 && scanProc.running
                Layout.fillWidth: true; implicitHeight: btScanRow.implicitHeight
                RowLayout {
                    id: btScanRow; anchors.left: parent.left; spacing: 6
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

            // ── CONNECTING STATE ──
            ColumnLayout {
                visible: btPop.popupState === "connecting"
                opacity: btPop.popupState === "connecting" ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }
                Layout.fillWidth: true; spacing: 8; Layout.alignment: Qt.AlignHCenter

                Text { text: "Connecting to " + btPop.targetDevice + "…"; color: Theme.fg
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
