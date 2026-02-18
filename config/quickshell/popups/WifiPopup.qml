import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PanelWindow {
    id: wifiPop
    property bool active: false; signal close()
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:wifi"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property string connectedSsid: ""
    ListModel { id: netModel }
    ListModel { id: knownModel }

    onActiveChanged: { if (active) { scan(); loadKnown(); } }

    function scan() { netModel.clear(); connectedSsid = ""; scanProc.running = true; }
    function loadKnown() { knownModel.clear(); knownProc.running = true; }

    function isKnown(ssid) {
        for (let i = 0; i < knownModel.count; i++) if (knownModel.get(i).name === ssid) return true;
        return false;
    }

    function connectTo(ssid) {
        if (isKnown(ssid)) {
            connectProc.command = ["nmcli", "dev", "wifi", "connect", ssid];
            connectProc.running = true;
        } else {
            nmtuiProc.running = true;
            wifiPop.close();
        }
    }

    Process {
        id: scanProc; command: ["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE", "dev", "wifi", "list"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let p = line.split(":"); if (p.length < 4 || !p[0]) return;
            if (p[3] === "*") wifiPop.connectedSsid = p[0];
            for (let i = 0; i < netModel.count; i++) if (netModel.get(i).ssid === p[0]) return;
            netModel.append({ ssid: p[0], signal: parseInt(p[1]) || 0, security: p[2] || "", active: p[3] === "*" });
        } }
    }
    Process {
        id: knownProc; command: ["nmcli", "-t", "-f", "NAME", "con", "show"]; running: false
        stdout: SplitParser { onRead: (line) => { if (line.trim()) knownModel.append({ name: line.trim() }); } }
    }
    Process { id: connectProc; running: false }
    Process { id: nmtuiProc; command: ["alacritty", "-e", "nmtui"]; running: false }

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: wifiPop.close()
        MouseArea { anchors.fill: parent; onClicked: wifiPop.close() }
    }

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth; height: wifiCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: wifiCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 8

            RowLayout { Layout.fillWidth: true
                Text { text: "󰖩  Wi-Fi"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true }
                Text { text: "Rescan"; color: rescanA.containsMouse ? Theme.blueBright : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    MouseArea { id: rescanA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: wifiPop.scan() } }
            }

            Text { visible: wifiPop.connectedSsid !== ""; text: "Connected: " + wifiPop.connectedSsid; color: Theme.greenBright; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            Flickable {
                Layout.fillWidth: true; Layout.maximumHeight: 280; Layout.minimumHeight: 30
                contentHeight: netCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: netCol; width: parent.width; spacing: 4
                    Repeater {
                        model: netModel
                        Rectangle {
                            id: netItem; required property string ssid; required property int signal
                            required property string security; required property bool active
                            width: netCol.width; height: 30; radius: 6
                            color: niArea.containsMouse ? Theme.bg2 : "transparent"

                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                                Text {
                                    text: { if (signal > 75) return "󰖩"; return "󰖩"; }
                                    color: { if (netItem.active) return Theme.greenBright; if (signal > 60) return Theme.fg; if (signal > 30) return Theme.fg3; return Theme.fg4; }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                                }
                                Text { text: netItem.ssid; color: netItem.active ? Theme.greenBright : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text { visible: netItem.security !== ""; text: "󰌾"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                                Text { text: netItem.signal + "%"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                            }
                            MouseArea { id: niArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: { if (!netItem.active) wifiPop.connectTo(netItem.ssid); } }
                        }
                    }
                }
            }
            Text { visible: netModel.count === 0; text: "Scanning..."; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        }
    }
}
