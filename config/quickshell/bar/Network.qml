import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

RowLayout {
    spacing: 4

    property string networkName: ""
    property bool connected: networkName !== ""

    Text {
        text: connected ? "󰖩" : "󰖪"
        color: connected ? Theme.fg : Theme.fg4
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }

    Text {
        text: networkName
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
        visible: connected
    }

    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("yes:")) {
                    networkName = line.substring(4);
                }
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            networkName = "";
            netProc.running = true;
        }
    }
}
