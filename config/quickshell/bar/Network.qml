import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

RowLayout {
    id: netRoot; spacing: 4; signal clicked()
    property string networkName: ""
    property bool connected: networkName !== ""

    // ── Debounced state: hold previous value until new data arrives ──
    // Instead of clearing networkName before each poll (which caused the flash),
    // we write into a staging property and only commit when we get a real answer.
    property string _pendingName: ""
    property bool _gotResult: false

    Text {
        id: netIcon
        text: connected ? "󰖩" : "󰖪"
        color: netArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize

        // Smooth icon swap: crossfade + subtle vertical slide
        Behavior on text {
            SequentialAnimation {
                NumberAnimation { target: netIcon; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                PropertyAction { target: netIcon; property: "text" }
                NumberAnimation { target: netIcon; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutBack }
            }
        }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Text {
        id: netLabel
        text: networkName
        visible: connected
        color: netArea.containsMouse ? Theme.yellowBright : Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall

        // Slide in from right when SSID appears
        opacity: connected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
        id: netArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: netRoot.clicked()
    }

    // ── Polling process ──
    // Key change: we do NOT clear networkName before polling.
    // The process writes into staging vars; we commit after stdout closes.
    Process {
        id: netProc
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID", "dev", "wifi"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                if (line.startsWith("yes:")) {
                    netRoot._pendingName = line.substring(4);
                    netRoot._gotResult = true;
                }
            }
        }
        onRunningChanged: {
            // When the process finishes, commit the result
            if (!running) {
                if (_gotResult) {
                    networkName = _pendingName;
                } else {
                    // nmcli returned no active connection → genuinely disconnected
                    networkName = "";
                }
                _pendingName = "";
                _gotResult = false;
            }
        }
    }

    Timer {
        interval: 10000; running: true; repeat: true
        onTriggered: {
            // Don't clear networkName! Just re-poll.
            _pendingName = "";
            _gotResult = false;
            netProc.running = true;
        }
    }
}
