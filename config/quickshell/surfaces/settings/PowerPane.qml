import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    Component.onCompleted: if (Sys.Host.laptop) Sys.Power.readChargeLimit()

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            title: "Battery"
            visible: Sys.Power.present

            Ui.ListRow {
                Layout.fillWidth: true
                icon: Sys.Power.icon
                iconColor: Sys.Power.low ? Theme.critical : Sys.Power.charging ? Theme.positive : Theme.textSecondary
                title: Sys.Power.percent + "%"
                subtitle: Sys.Power.full ? "Fully charged" : Sys.Power.charging ? "Charging" : "On battery"
                interactive: false
            }
        }

        Ui.Group {
            title: "Performance"
            visible: Sys.Host.profileSwitching
            footnote: "Backend: " + Sys.Power.backend

            Repeater {
                model: Sys.Power.profiles

                Ui.ListRow {
                    id: row

                    required property var modelData
                    readonly property bool chosen: Sys.Power.profile === row.modelData.id

                    Layout.fillWidth: true
                    icon: modelData.icon
                    title: modelData.label
                    selected: row.chosen
                    opacity: row.chosen && Sys.Power.switching ? Theme.pendingAlpha : 1
                    onClicked: Sys.Power.setProfile(row.modelData.id)

                    Behavior on opacity {
                        Ui.Anim {}
                    }

                    Ui.Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "circle-check-filled"
                        color: Theme.accent
                        visible: row.chosen
                    }
                }
            }
        }

        Ui.Group {
            title: "Charge limit"
            visible: Sys.Host.laptop
            footnote: Sys.Power.chargeError !== "" ? Sys.Power.chargeError : Sys.Power.chargeKnown ? "Charging mode: " + Sys.Power.chargeMode : ""

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "bolt"
                title: "Limit charging"
                subtitle: Sys.Power.chargeCapped ? "Stops at " + (Sys.Power.chargeStop > 0 ? Sys.Power.chargeStop : Sys.Power.chargeCeiling) + "%" : "Charge to full"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Power.chargeCapped
                    pending: Sys.Power.chargeBusy
                    onToggled: enabled => Sys.Power.setChargeLimit(enabled)
                }
            }
        }

        Ui.Group {
            title: "Keep awake"

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "zzz"
                title: "Prevent idle sleep"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Idle.inhibited
                    onToggled: Sys.Idle.toggle()
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                visible: Sys.Host.laptop
                icon: "laptop"
                title: "Ignore lid close"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Idle.lidInhibited
                    onToggled: Sys.Idle.toggleLid()
                }
            }
        }
    }
}
