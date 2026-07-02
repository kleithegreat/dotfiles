import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../components" as Components

Components.WheelFlickable {
    id: root
    anchors.fill: parent
    contentHeight: powerCol.implicitHeight
    clip: true

    Component.onCompleted: {
        PowerProfileService.detect();
        PowerProfileService.detectChargeLimit();
    }

    property real batPct: {
        let r = UPower.displayDevice.percentage;
        return (r <= 1.0 && r > 0) ? r * 100 : r;
    }
    property bool charging: UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged

    ColumnLayout {
        id: powerCol
        width: parent.width
        spacing: 16

        // Header
        Components.SettingsPaneHeader { title: "Power"; iconSource: "../icons/bolt.svg" }

        // Power profile
        Components.SectionLabel { text: "POWER PROFILE" }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: PowerProfileService.availableProfiles
                Rectangle {
                    id: ppBtn
                    required property var modelData
                    property bool isCur: PowerProfileService.currentProfile === modelData.name
                    property bool isPending: PowerProfileService.pendingProfile === modelData.name && !isCur

                    Layout.fillWidth: true
                    height: 48
                    radius: Theme.hoverRadius
                    color: isCur ? Theme.blueBright : (ppArea.containsMouse ? Theme.bg2 : Theme.bg1)
                    border.width: 1
                    border.color: isCur ? Theme.blueBright : Theme.bg3
                    Behavior on color { Components.StdCAnim { duration: Theme.animSpring } }
                    Behavior on border.color { Components.StdCAnim { duration: Theme.animSpring } }
                    scale: ppArea.pressed ? 0.95 : 1.0
                    Behavior on scale { Components.StdAnim { duration: Theme.animMicro } }
                    transformOrigin: Item.Center

                    Rectangle {
                        id: pendingGlow
                        anchors.fill: parent; radius: parent.radius
                        color: "transparent"; border.width: 1; border.color: Theme.blueBright
                        visible: ppBtn.isPending; opacity: 0
                        SequentialAnimation {
                            running: ppBtn.isPending; loops: Animation.Infinite
                            NumberAnimation { target: pendingGlow; property: "opacity"; to: 1.0; duration: 600; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: pendingGlow; property: "opacity"; to: 0.3; duration: 600; easing.type: Easing.InOutCubic }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 2

                        Components.Icon {
                            source: ppBtn.modelData.icon
                            color: ppBtn.isCur ? Theme.bg : (ppBtn.isPending ? Theme.blueBright : Theme.fg3)
                            Layout.alignment: Qt.AlignHCenter
                            Behavior on color { Components.StdCAnim { duration: Theme.animSpring } }
                        }

                        Text {
                            text: ppBtn.modelData.label
                            color: ppBtn.isCur ? Theme.bg : (ppBtn.isPending ? Theme.fg : Theme.fg3)
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeMini
                            font.bold: ppBtn.isCur
                            Layout.alignment: Qt.AlignHCenter
                            Behavior on color { Components.StdCAnim { duration: Theme.animSpring } }
                        }
                    }

                    Components.HoverLayer {
                        id: ppArea
                        flat: true
                        onClicked: PowerProfileService.setProfile(ppBtn.modelData.name)
                    }
                }
            }
        }

        Text {
            visible: PowerProfileService.backend === "laptop-helper"
            text: "E-Cores leaves the boot P-core online because Linux does not expose cpu0 hot-unplug on this host."
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMini
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // Battery
        Components.Divider {}

        Components.SectionLabel { text: "BATTERY" }

        Text {
            text: "Battery: " + Math.round(root.batPct) + "%" + (root.charging ? " (Charging)" : " (Discharging)")
            color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            visible: PowerProfileService.backend === "autocpufreq"
            text: "Using auto-cpufreq (pkexec for changes)"
            color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
        }

        // Charge limit
        Components.Divider {}

        Components.SectionLabel { text: "CHARGE LIMIT" }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Battery Charge Cap"
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter
                }

                Text {
                    text: PowerProfileService.chargeLimitStateText
                    color: PowerProfileService.chargeLimitError !== "" ? Theme.redBright : (PowerProfileService.chargeLimitEnabled ? Theme.fg3 : Theme.fg4)
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.alignment: Qt.AlignVCenter
                }

                Components.ToggleSwitch {
                    checked: PowerProfileService.chargeLimitEnabled
                    opacity: PowerProfileService.chargeLimitBusy ? 0.65 : 1.0
                    onToggled: PowerProfileService.setChargeLimit(!PowerProfileService.chargeLimitEnabled)
                }
            }

            Text {
                text: PowerProfileService.chargeLimitDetailText
                color: PowerProfileService.chargeLimitError !== "" ? Theme.redBright : Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
        }
    }
}
