import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../components" as Components

RowLayout {
    id: batRoot; spacing: 4; visible: UPower.displayDevice.isPresent
    signal clicked()

    // UPowerDevice.percentage is always 0..1
    readonly property real pct: UPower.displayDevice.percentage * 100
    readonly property string tooltipText: "Battery: " + Math.round(pct) + "%" + (charging ? " (Charging)" : "")

    // Debounced charging state
    // UPower can transiently report Discharging during AC state transitions.
    // We delay "unplug" events by 2s but reflect "plug in" instantly.
    readonly property bool _rawCharging: UPower.displayDevice.state === UPowerDeviceState.Charging
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

    Components.StyledIcon {
        id: batIcon
        animate: true
        source: {
            if (charging) return "../icons/battery-charging.svg";
            if (pct > 90) return "../icons/battery-full.svg";
            if (pct > 70) return "../icons/battery-high.svg";
            if (pct > 50) return "../icons/battery-medium.svg";
            return "../icons/battery-low.svg";
        }
        color: {
            if (batArea.containsMouse) return Theme.yellowBright;
            if (charging) return Theme.greenBright;
            if (pct < 15) return Theme.redBright;
            if (pct < 30) return Theme.yellowBright;
            return Theme.fg;
        }

        Behavior on color { Components.CAnim { duration: Theme.animHover } }
    }

    Components.StyledText {
        visible: pct <= 25 && !charging
        text: Math.round(pct) + "%"
        font.pixelSize: Theme.fontSizeSmall
        color: batIcon.color
    }

    Components.BarTooltipArea {
        id: batArea; tip: batRoot.tooltipText
        onClicked: batRoot.clicked()
    }
}
