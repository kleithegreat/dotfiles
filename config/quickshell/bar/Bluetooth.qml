import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

RowLayout {
    id: btRoot; spacing: 4; signal clicked()
    property string deviceName: ""
    property bool powered: false
    property bool connected: deviceName !== ""
    property int maxLabelWidth: 100

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
                NumberAnimation { target: btIcon; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                PropertyAction { target: btIcon; property: "text" }
                NumberAnimation { target: btIcon; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
            }
        }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Item {
        id: marqueeContainer
        visible: connected
        Layout.maximumWidth: btRoot.maxLabelWidth
        implicitWidth: Math.min(btLabel.implicitWidth, btRoot.maxLabelWidth)
        implicitHeight: btLabel.implicitHeight
        clip: true

        opacity: connected ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        property bool overflowing: btLabel.implicitWidth > btRoot.maxLabelWidth

        Text {
            id: btLabel
            text: deviceName
            y: 0
            color: btArea.containsMouse ? Theme.yellowBright : Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        SequentialAnimation {
            id: marqueeAnim
            running: marqueeContainer.overflowing && marqueeContainer.visible
            loops: Animation.Infinite

            PauseAnimation { duration: 2000 }
            NumberAnimation {
                target: btLabel; property: "x"
                from: 0; to: -(btLabel.implicitWidth - btRoot.maxLabelWidth)
                duration: Math.max(1500, (btLabel.implicitWidth - btRoot.maxLabelWidth) * 30)
                easing.type: Easing.Linear
            }
            PauseAnimation { duration: 1500 }
            PropertyAction { target: btLabel; property: "x"; value: 0 }
        }

        onOverflowingChanged: { marqueeAnim.stop(); btLabel.x = 0; }
        Connections {
            target: btRoot
            function onDeviceNameChanged() { marqueeAnim.stop(); btLabel.x = 0; }
        }
    }

    MouseArea {
        id: btArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: btRoot.clicked()
    }

    // ── Poll: bluetoothctl show (adapter power) ──
    Process {
        id: showProc
        command: ["bluetoothctl", "show"]
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
        command: ["bluetoothctl", "info"]
        running: true
        stdout: SplitParser { onRead: (line) => {
            let t = line.trim();
            if (t.startsWith("Name:")) {
                btRoot._pendingName = t.substring(5).trim();
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
