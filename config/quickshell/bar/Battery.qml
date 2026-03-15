import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

RowLayout {
    id: batRoot; spacing: 4; visible: UPower.displayDevice.isPresent
    signal clicked()

    property real rawPct: UPower.displayDevice.percentage
    property real pct: rawPct <= 1.0 && rawPct > 0 ? rawPct * 100 : rawPct

    // ── Debounced charging state ──
    // UPower can transiently report Discharging during AC state transitions.
    // We delay "unplug" events by 2s but reflect "plug in" instantly.
    property bool _rawCharging: UPower.displayDevice.state === UPowerDeviceState.Charging
                                || UPower.displayDevice.state === UPowerDeviceState.FullyCharged
    property bool charging: _rawCharging

    on_RawChargingChanged: {
        if (_rawCharging) {
            // Plugged in → reflect immediately, cancel any pending "unplug"
            _debounceTimer.stop();
            charging = true;
        } else {
            // Unplugged → wait before reflecting to filter transient glitches
            _debounceTimer.restart();
        }
    }
    Timer {
        id: _debounceTimer; interval: 2000
        onTriggered: batRoot.charging = batRoot._rawCharging
    }

    Text {
        id: batIcon
        text: {
            if (charging) return "󰂄";
            if (pct > 90) return "󰁹";
            if (pct > 70) return "󰂂";
            if (pct > 50) return "󰁿";
            if (pct > 30) return "󰁽";
            return "󰁺";
        }
        color: {
            if (batArea.containsMouse) return Theme.yellowBright;
            if (charging) return Theme.greenBright;
            if (pct < 15) return Theme.redBright;
            if (pct < 30) return Theme.yellowBright;
            return Theme.fg;
        }
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize

        // Smooth icon swap with scale bounce (like caelestia status icons)
        Behavior on text {
            SequentialAnimation {
                ParallelAnimation {
                    NumberAnimation { target: batIcon; property: "opacity"; to: 0; duration: 100; easing.type: Easing.InQuad }
                    NumberAnimation { target: batIcon; property: "scale"; to: 0.6; duration: 100; easing.type: Easing.InQuad }
                }
                PropertyAction { target: batIcon; property: "text" }
                ParallelAnimation {
                    NumberAnimation { target: batIcon; property: "opacity"; to: 1; duration: 250; easing.type: Easing.OutBack }
                    NumberAnimation { target: batIcon; property: "scale"; to: 1.0; duration: 300; easing.type: Easing.OutBack; }
                }
            }
        }
        Behavior on color { ColorAnimation { duration: 200 } }
    }

    Text {
        id: batLabel
        text: Math.round(pct) + "%"
        color: batArea.containsMouse ? Theme.yellowBright : Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    MouseArea {
        id: batArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: batRoot.clicked()
    }
}
