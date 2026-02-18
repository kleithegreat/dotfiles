import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

RowLayout {
    spacing: 4
    visible: UPower.displayDevice.isPresent

    property real rawPercent: UPower.displayDevice.percentage
    property real percent: rawPercent <= 1.0 && rawPercent > 0 ? rawPercent * 100 : rawPercent
    property bool charging: UPower.displayDevice.state === UPowerDeviceState.Charging
                         || UPower.displayDevice.state === UPowerDeviceState.FullyCharged

    Text {
        text: {
            if (charging) return "󰂄";
            if (percent > 90) return "󰁹";
            if (percent > 70) return "󰂂";
            if (percent > 50) return "󰁿";
            if (percent > 30) return "󰁽";
            return "󰁺";
        }
        color: {
            if (charging) return Theme.greenBright;
            if (percent < 15) return Theme.redBright;
            if (percent < 30) return Theme.yellowBright;
            return Theme.fg;
        }
        font.family: Theme.fontFamily
        font.pixelSize: Theme.iconSize
    }

    Text {
        text: Math.round(percent) + "%"
        color: Theme.fg
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeSmall
    }
}
