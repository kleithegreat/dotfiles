import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

RowLayout {
    id: netRoot; spacing: 4; signal clicked()
    property string networkName: ""
    property bool connected: networkName !== ""
    property int maxLabelWidth: 100

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
                NumberAnimation { target: netIcon; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Item {
        id: marqueeContainer
        visible: connected
        Layout.maximumWidth: netRoot.maxLabelWidth
        implicitWidth: Math.min(netLabel.implicitWidth, netRoot.maxLabelWidth)
        implicitHeight: netLabel.implicitHeight
        clip: true

        opacity: connected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        property bool overflowing: netLabel.implicitWidth > netRoot.maxLabelWidth

        Text {
            id: netLabel
            text: networkName
            y: 0
            color: netArea.containsMouse ? Theme.yellowBright : Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall

            Behavior on color { ColorAnimation { duration: 150 } }
        }

        SequentialAnimation {
            id: marqueeAnim
            running: marqueeContainer.overflowing && marqueeContainer.visible
            loops: Animation.Infinite

            PauseAnimation { duration: 2000 }
            NumberAnimation {
                target: netLabel; property: "x"
                from: 0; to: -(netLabel.implicitWidth - netRoot.maxLabelWidth)
                duration: Math.max(1500, (netLabel.implicitWidth - netRoot.maxLabelWidth) * 30)
                easing.type: Easing.Linear
            }
            PauseAnimation { duration: 1500 }
            PropertyAction { target: netLabel; property: "x"; value: 0 }
        }

        onOverflowingChanged: {
            marqueeAnim.stop();
            netLabel.x = 0;
        }

        Connections {
            target: netRoot
            function onNetworkNameChanged() {
                marqueeAnim.stop();
                netLabel.x = 0;
            }
        }
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
