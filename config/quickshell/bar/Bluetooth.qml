import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

RowLayout {
    id: btRoot; spacing: 4; signal clicked()
    readonly property string deviceName: BluetoothService.connectedName
    readonly property bool powered: BluetoothService.powered
    readonly property bool connected: deviceName !== ""
    readonly property string tooltipText: {
        if (connected) return deviceName;
        if (powered) return "Bluetooth on";
        return "Bluetooth off";
    }

    Components.StyledIcon {
        id: btIcon
        animate: true
        source: connected ? "../icons/bluetooth-connected.svg" : (powered ? "../icons/bluetooth-on.svg" : "../icons/bluetooth-off.svg")
        color: btArea.containsMouse ? Theme.yellowBright : (connected ? Theme.fg : Theme.fg4)
        Behavior on color { Components.CAnim { duration: Theme.animHover } }
    }

    Components.BarTooltipArea {
        id: btArea; tip: btRoot.tooltipText
        onClicked: btRoot.clicked()
    }
}
