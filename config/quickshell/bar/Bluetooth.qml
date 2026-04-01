import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components" as Components

RowLayout {
    id: btRoot; spacing: 4; signal clicked()
    property string deviceName: ""
    property bool powered: false
    property bool connected: deviceName !== ""
    // ── Debounced state: staging vars ──
    property string _pendingName: ""
    property bool _pendingPowered: false
    property bool _gotInfo: false
    property bool _gotShow: false
    property int _pendingSteps: 0

    Text {
        id: btIcon
        text: connected ? "󰂱" : (powered ? "󰂯" : "󰂲")
        color: btArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize

        Behavior on text {
            SequentialAnimation {
                Components.Anim { target: btIcon; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                PropertyAction { target: btIcon; property: "text" }
                Components.Anim { target: btIcon; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        Behavior on color { Components.CAnim { duration: 150 } }
    }

    MouseArea {
        id: btArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: btRoot.clicked()
    }

    // ── Poll: bluetoothctl show (adapter power) ──
    Process {
        id: showProc
        command: ["bluetoothctl", "--timeout", "2", "show"]
        running: true
        stdout: SplitParser { onRead: (line) => {
            let t = line.trim();
            if (t.startsWith("Powered:")) {
                btRoot._pendingPowered = t.indexOf("yes") >= 0;
                btRoot._gotShow = true;
            }
        } }
        onRunningChanged: {
            if (!running) { btRoot._checkCommit(); }
        }
    }

    // ── Poll: bluetoothctl info (connected device) ──
    Process {
        id: infoProc
        command: ["bluetoothctl", "--timeout", "2", "devices", "Connected"]
        running: true
        stdout: SplitParser { onRead: (line) => {
            let t = line.trim();
            let match = t.match(/^Device\s+\S+\s+(.+)$/);
            if (match) {
                btRoot._pendingName = match[1];
                btRoot._gotInfo = true;
            }
        } }
        onRunningChanged: {
            if (!running) { btRoot._checkCommit(); }
        }
    }

    function _checkCommit() {
        _pendingSteps++;
        if (_pendingSteps < 2) return;
        // Both processes done — commit
        powered = _pendingPowered;
        if (_gotInfo) {
            deviceName = _pendingName;
        } else {
            deviceName = "";
        }
        _pendingName = "";
        _pendingPowered = false;
        _gotInfo = false;
        _gotShow = false;
        _pendingSteps = 0;
    }

    Timer {
        interval: 10000; running: true; repeat: true
        onTriggered: {
            btRoot._pendingName = "";
            btRoot._pendingPowered = false;
            btRoot._gotInfo = false;
            btRoot._gotShow = false;
            btRoot._pendingSteps = 0;
            showProc.running = true;
            infoProc.running = true;
        }
    }
}
