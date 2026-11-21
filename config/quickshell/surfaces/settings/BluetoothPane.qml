import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    Component.onCompleted: Sys.Bluetooth.seek("settings", true)
    Component.onDestruction: Sys.Bluetooth.seek("settings", false)

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
            title: Sys.AirPods.link?.name ?? ""
            visible: Sys.AirPods.connected

            Ui.PodBattery {
                Layout.fillWidth: true
                Layout.margins: Metrics.rowInset
                battery: Sys.AirPods.battery
            }

            Ui.ListRow {
                Layout.fillWidth: true
                visible: Sys.AirPods.hasNoise
                title: "Noise control"
                interactive: false
            }

            Ui.Choice {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.rowInset
                Layout.rightMargin: Metrics.rowInset
                Layout.bottomMargin: Metrics.rowInset
                visible: Sys.AirPods.hasNoise
                options: Sys.AirPods.noiseModes
                current: Sys.AirPods.noise
                onPicked: mode => Sys.AirPods.setNoise(mode)
            }

            Ui.ListRow {
                Layout.fillWidth: true
                visible: Sys.AirPods.hasAwareness
                title: "Conversation awareness"
                subtitle: "Lowers media and lets voices through when you speak"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.AirPods.awareness
                    onToggled: Sys.AirPods.setAwareness(!Sys.AirPods.awareness)
                }
            }
        }

        Ui.Group {
            title: "AirPods nearby"

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Show an open case"
                subtitle: "A case can't say whose it is, only how close it is"
                interactive: false
            }

            Ui.Choice {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.rowInset
                Layout.rightMargin: Metrics.rowInset
                Layout.bottomMargin: Metrics.rowInset
                options: Sys.AirPods.reaches
                current: Sys.AirPods.reach
                onPicked: value => Sys.AirPods.setReach(value)
            }
        }

        Ui.Group {
            title: Sys.Bluetooth.discovering ? "Nearby · scanning" : "Nearby"
            visible: Sys.Bluetooth.powered

            Repeater {
                model: Sys.Bluetooth.discovered

                Ui.ListRow {
                    id: nearbyRow
                    required property var modelData
                    readonly property bool pairing: Sys.Bluetooth.pairingAddress === nearbyRow.modelData.address

                    Layout.fillWidth: true
                    icon: "bluetooth-on"
                    title: nearbyRow.modelData.name
                    subtitle: nearbyRow.pairing ? "Pairing…" : nearbyRow.modelData.address
                    chevron: !nearbyRow.pairing
                    interactive: Sys.Bluetooth.pairingAddress === ""
                    opacity: nearbyRow.pairing ? Theme.pendingAlpha : 1.0
                    onClicked: Sys.Bluetooth.pair(nearbyRow.modelData)
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
