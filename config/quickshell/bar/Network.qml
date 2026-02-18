import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

RowLayout {
    id: netRoot; spacing: 4; signal clicked()
    property string networkName: ""
    property bool connected: networkName !== ""

    Text {
        text: connected ? "󰖩" : "󰖪"
        color: netArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
    }
    Text {
        text: networkName; visible: connected
        color: netArea.containsMouse ? Theme.yellowBright : Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
    }
    MouseArea {
        id: netArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: netRoot.clicked()
    }
    Process {
        id: netProc; command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]; running: true
        stdout: SplitParser { onRead: (line) => { if (line.startsWith("yes:")) networkName = line.substring(4); } }
    }
    Timer { interval: 10000; running: true; repeat: true; onTriggered: { networkName = ""; netProc.running = true; } }
}
