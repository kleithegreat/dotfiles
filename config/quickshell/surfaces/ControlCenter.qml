import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Popover {
    id: root

    required property ShellState state

    shown: state.isOpen("control")
    anchor: state.anchor
    panelWidth: Metrics.panelWide
    contentHeight: stack.implicitHeight

    ColumnLayout {
        id: stack
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Metrics.s3

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Metrics.s2
            rowSpacing: Metrics.s2

            Ui.Tile {
                Layout.fillWidth: true
                icon: Sys.Network.icon
                title: "Wi-Fi"
                detail: Sys.Network.wifiRadio ? Sys.Network.linkType === "wifi" ? Sys.Network.ssid : "Not connected" : "Off"
                on: Sys.Network.wifiRadio
                pending: Sys.Network.radioBusy
                expandable: true
                onClicked: Sys.Network.toggleWifiRadio()
                onExpand: root.state.showSettings("Network")
            }

            Ui.Tile {
                Layout.fillWidth: true
                visible: Sys.Bluetooth.available
                icon: Sys.Bluetooth.icon
                title: "Bluetooth"
                detail: Sys.Bluetooth.label
                on: Sys.Bluetooth.powered
                expandable: true
                onClicked: Sys.Bluetooth.togglePower()
                onExpand: root.state.showSettings("Bluetooth")
            }

            Ui.Tile {
                Layout.fillWidth: true
                icon: "shield-lock"
                title: "Mullvad"
                detail: Sys.Mullvad.connected ? Sys.Mullvad.location : Sys.Mullvad.state === "connecting" ? "Connecting" : "Off"
                on: Sys.Mullvad.connected
                pending: Sys.Mullvad.busy
                expandable: true
                onClicked: Sys.Mullvad.toggle()
                onExpand: root.state.showSettings("Network")
            }

            Ui.Tile {
                Layout.fillWidth: true
                icon: "tailscale"
                title: "Tailscale"
                detail: Sys.Tailscale.up ? Sys.Tailscale.ip : "Off"
                on: Sys.Tailscale.up
                pending: Sys.Tailscale.busy
                onClicked: Sys.Tailscale.toggle()
            }

            Ui.Tile {
                Layout.fillWidth: true
                icon: Sys.Notifications.dnd ? "bell-off" : "bell"
                title: "Do Not Disturb"
                detail: Sys.Notifications.dnd ? "On" : "Off"
                on: Sys.Notifications.dnd
                expandable: true
                onClicked: Sys.Notifications.toggleDnd()
                onExpand: root.state.showSettings("Notifications")
            }

            Ui.Tile {
                Layout.fillWidth: true
                icon: "night-light"
                title: "Night Light"
                detail: Sys.NightLight.mode === "auto" ? Sys.NightLight.running ? "Auto · " + Sys.NightLight.temperature + "K" : "Auto" : Sys.NightLight.running ? Sys.NightLight.target + "K" : "Off"
                on: Sys.NightLight.running
                pending: Sys.NightLight.busy
                expandable: true
                onClicked: Sys.NightLight.toggle(!Sys.NightLight.running)
                onExpand: root.state.showSettings("Display")
            }

            Ui.Tile {
                Layout.fillWidth: true
                icon: "zzz"
                title: "Keep Awake"
                detail: Sys.Idle.inhibited ? "On" : "Off"
                on: Sys.Idle.inhibited
                onClicked: Sys.Idle.toggle()
            }
        }

        Ui.Divider {}

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.s3

            Ui.Pressable {
                implicitWidth: Metrics.s6
                implicitHeight: Metrics.s6
                radius: Metrics.rControl
                onClicked: Sys.Audio.toggleMute()

                Ui.Icon {
                    anchors.centerIn: parent
                    name: Sys.Audio.icon
                    color: Sys.Audio.muted ? Theme.textQuaternary : Theme.textSecondary
                }
            }

            Ui.Slider {
                id: volume
                Layout.fillWidth: true
                value: Sys.Audio.volume
                claimsDrag: false
                onMoved: level => Sys.Audio.setVolume(level)
            }

            Ui.Label {
                text: Sys.Audio.percent + "%"
                role: "caption"
                numeric: true
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: Metrics.s8
            }
        }

        // While the pointer owns the value, the OSD would be a second, worse
        // copy of the control already under the cursor.
        Binding {
            target: Sys.Osd
            property: "suppressed"
            value: true
            when: volume.pressed
        }

        // The service rebuilds its device array on every write, so a Repeater
        // bound to the array itself is destroyed and rebuilt mid-gesture —
        // taking the MouseArea holding the pointer grab with it, which reduces
        // the slider to click-only. Key the model on the count and index in.
        Repeater {
            model: Sys.Brightness.devices.length

            RowLayout {
                id: lamp

                required property int index
                readonly property var device: Sys.Brightness.devices[lamp.index]

                Layout.fillWidth: true
                spacing: Metrics.s3

                Ui.Icon {
                    name: Sys.Brightness.icon
                    color: Theme.textSecondary
                    Layout.preferredWidth: Metrics.s6
                    Layout.alignment: Qt.AlignVCenter
                }

                Ui.Slider {
                    id: level
                    Layout.fillWidth: true
                    minimum: 0.01
                    value: lamp.device ? lamp.device.fraction : 0
                    claimsDrag: false
                    onMoved: fraction => {
                        if (lamp.device)
                            Sys.Brightness.set(lamp.device.device, fraction);
                    }
                }

                Ui.Label {
                    text: (lamp.device ? lamp.device.percent : 0) + "%"
                    role: "caption"
                    numeric: true
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: Metrics.s8
                }
            }
        }

        Ui.Divider {}

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.s2

            Ui.Button {
                text: "Settings"
                icon: "adjustments"
                onClicked: root.state.showSettings()
            }

            Item {
                Layout.fillWidth: true
            }

            Repeater {
                model: Sys.Host.profileSwitching ? Sys.Power.profiles : []

                Ui.Pressable {
                    id: chip

                    required property var modelData

                    implicitWidth: Metrics.s6 + Metrics.s1
                    implicitHeight: Metrics.controlHeight
                    radius: Metrics.rControl
                    active: Sys.Power.profile === chip.modelData.id
                    onClicked: Sys.Power.setProfile(chip.modelData.id)

                    Ui.Icon {
                        anchors.centerIn: parent
                        name: chip.modelData.icon
                        color: Sys.Power.profile === chip.modelData.id ? Theme.accent : Theme.textTertiary
                    }
                }
            }
        }
    }
}
