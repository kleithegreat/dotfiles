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
    boundsBehavior: Flickable.StopAtBounds

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

        // ── Power Profile ────────────────────────────────────

        Text { text: "POWER PROFILE"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Repeater {
            model: [
                { name: "performance", label: "Performance", icon: "󰵣", desc: "Max speed, more heat" },
                { name: "balanced",    label: "Balanced",    icon: "󰓅", desc: "Auto / default" },
                { name: "power-saver", label: "Power Saver", icon: "󰸲",  desc: "Extend battery life" }
            ]
            Rectangle {
                id: ppBtn; required property var modelData; required property int index
                Layout.fillWidth: true; height: 38; radius: Theme.hoverRadius
                property bool isCur: PowerProfileService.currentProfile === modelData.name
                property bool isPending: PowerProfileService.pendingProfile === modelData.name && !isCur
                color: "transparent"

                Rectangle {
                    anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                    opacity: ppBtn.isCur ? 0.8 : (ppBtn.isPending ? 0.5 : (ppBtnA.pressed ? 0.9 : (ppBtnA.containsMouse ? 0.6 : 0)))
                    Behavior on opacity {
                        Components.Anim { duration: Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                    }
                }

                Rectangle {
                    id: pendingIndicator
                    anchors.fill: parent; radius: parent.radius
                    color: "transparent"; border.width: 1; border.color: Theme.blueBright
                    visible: ppBtn.isPending; opacity: 0
                    SequentialAnimation {
                        running: ppBtn.isPending; loops: Animation.Infinite
                        NumberAnimation { target: pendingIndicator; property: "opacity"; to: 1.0; duration: 600; easing.type: Easing.InOutCubic }
                        NumberAnimation { target: pendingIndicator; property: "opacity"; to: 0.3; duration: 600; easing.type: Easing.InOutCubic }
                    }
                }

                border.width: ppBtn.isCur ? 1 : 0; border.color: Theme.blueBright
                Behavior on border.width {
                    Components.Anim { duration: Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                }

                Components.HoverLayer {
                    id: ppBtnA; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 0.98
                    onClicked: PowerProfileService.setProfile(ppBtn.modelData.name)

                    RowLayout { anchors.fill: parent; anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: Theme.listItemPadding; spacing: 8
                        Text { text: ppBtn.modelData.icon
                            color: (ppBtn.isCur || ppBtn.isPending) ? Theme.blueBright : Theme.fg
                            Behavior on color { Components.CAnim { duration: Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
                        ColumnLayout { spacing: 0; Layout.fillWidth: true
                            Text { text: ppBtn.modelData.label; color: (ppBtn.isCur || ppBtn.isPending) ? Theme.fg : Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: ppBtn.isCur }
                            Text { text: ppBtn.modelData.desc; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                        }
                    }
                }
            }
        }

        // ── Battery ──────────────────────────────────────────

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "BATTERY"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Text {
            text: "Battery: " + Math.round(root.batPct) + "%" + (root.charging ? " (Charging)" : " (Discharging)")
            color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
        }

        Text {
            visible: PowerProfileService.backend === "autocpufreq"
            text: "Using auto-cpufreq (pkexec for changes)"
            color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
        }

        // ── Charge Limit ─────────────────────────────────────

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "CHARGE LIMIT"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

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
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                wrapMode: Text.WordWrap; Layout.fillWidth: true
            }
        }
    }
}
