import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components" as Components

RowLayout {
    id: netRoot; spacing: 4; signal clicked()
    property string networkName: ""
    property string connectionType: ""
    property bool connected: networkName !== ""
    // ── Debounced state: hold previous value until new data arrives ──
    // Instead of clearing networkName before each poll (which caused the flash),
    // we write into a staging property and only commit when we get a real answer.
    property string _pendingName: ""
    property string _pendingType: ""
    property bool _gotResult: false

    Text {
        id: netIcon
        text: !connected ? "󰖪" : (connectionType === "ethernet" ? "󰈀" : "󰖩")
        color: netArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize

        // Smooth icon swap: crossfade + subtle vertical slide
        Behavior on text {
            SequentialAnimation {
                Components.Anim { target: netIcon; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                PropertyAction { target: netIcon; property: "text" }
                Components.Anim { target: netIcon; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        Behavior on color { Components.CAnim { duration: 150 } }
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
        command: ["nmcli", "-t", "-f", "TYPE,STATE,CONNECTION", "device", "status"]
        running: true
        stdout: SplitParser {
            onRead: (line) => {
                const parts = line.split(":");
                if (parts.length >= 2 && parts[1] === "connected") {
                    const type = parts[0];
                    const connection = parts.length >= 3 ? parts.slice(2).join(":") : "";
                    if (type === "ethernet") {
                        netRoot._pendingType = "ethernet";
                        netRoot._pendingName = "Ethernet";
                        netRoot._gotResult = true;
                    } else if (type === "wifi" && netRoot._pendingType !== "ethernet") {
                        netRoot._pendingType = "wifi";
                        netRoot._pendingName = connection;
                        netRoot._gotResult = true;
                    }
                }
            }
        }
        onRunningChanged: {
            // When the process finishes, commit the result
            if (!running) {
                if (_gotResult) {
                    networkName = _pendingName;
                    connectionType = _pendingType;
                } else {
                    // nmcli returned no active connection → genuinely disconnected
                    networkName = "";
                    connectionType = "";
                }
                _pendingName = "";
                _pendingType = "";
                _gotResult = false;
            }
        }
    }

    Timer {
        interval: 10000; running: true; repeat: true
        onTriggered: {
            // Don't clear networkName! Just re-poll.
            _pendingName = "";
            _pendingType = "";
            _gotResult = false;
            netProc.running = true;
        }
    }
}
