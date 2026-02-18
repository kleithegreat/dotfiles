import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower

RowLayout {
    id: batRoot; spacing: 4; visible: UPower.displayDevice.isPresent
    signal clicked()

    property real rawPct: UPower.displayDevice.percentage
    property real pct: rawPct <= 1.0 && rawPct > 0 ? rawPct * 100 : rawPct
    property bool charging: UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged

    Text {
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
    }
    Text {
        text: Math.round(pct) + "%"
        color: batArea.containsMouse ? Theme.yellowBright : Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
    }
    MouseArea {
        id: batArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: batRoot.clicked()
    }
}
