import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    Component.onCompleted: Sys.Bluetooth.setDiscovering(true)
    Component.onDestruction: Sys.Bluetooth.setDiscovering(false)

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            Ui.ListRow {
                Layout.fillWidth: true
                icon: Sys.Bluetooth.icon
                title: "Bluetooth"
                subtitle: Sys.Bluetooth.available ? Sys.Bluetooth.label : "No adapter"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Bluetooth.powered
                    interactive: Sys.Bluetooth.available
                    onToggled: Sys.Bluetooth.togglePower()
                }
            }
        }

        Ui.Group {
            title: "My devices"
            visible: Sys.Bluetooth.connected.length + Sys.Bluetooth.paired.length > 0

            Repeater {
                model: Sys.Bluetooth.connected.concat(Sys.Bluetooth.paired)

                Ui.ListRow {
                    id: device

                    required property var modelData

                    Layout.fillWidth: true
                    icon: modelData.connected ? "bluetooth-connected" : "bluetooth-on"
                    iconColor: modelData.connected ? Theme.accent : Theme.textSecondary
                    title: modelData.name
                    subtitle: {
                        const battery = Sys.Bluetooth.batteryFor(device.modelData);
                        const state = device.modelData.connected ? "Connected" : "Paired";
                        return battery >= 0 ? state + " · " + battery + "%" : state;
                    }
                    onClicked: modelData.connected ? Sys.Bluetooth.disconnect(modelData) : Sys.Bluetooth.connect(modelData)

                    Ui.Button {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Forget"
                        onClicked: Sys.Bluetooth.forget(device.modelData)
                    }
                }
            }
        }

        Ui.Group {
            title: Sys.Bluetooth.discovering ? "Nearby · scanning" : "Nearby"
            visible: Sys.Bluetooth.powered

            Repeater {
                model: Sys.Bluetooth.discovered

                Ui.ListRow {
                    required property var modelData

                    Layout.fillWidth: true
                    icon: "bluetooth-on"
                    title: modelData.name
                    subtitle: modelData.address
                    chevron: true
                    onClicked: Sys.Bluetooth.pair(modelData)
                }
            }

            Ui.ListRow {
                Layout.fillWidth: true
                visible: Sys.Bluetooth.discovered.length === 0
                title: Sys.Bluetooth.discovering ? "Looking for devices" : "No devices found"
                interactive: false
            }
        }
    }
}
