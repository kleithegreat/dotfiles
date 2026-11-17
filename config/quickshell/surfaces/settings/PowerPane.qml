import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    readonly property var history: Sys.Power.history
    readonly property var levels: history.levels ?? []
    readonly property var hours: history.hours ?? []
    readonly property var apps: history.apps ?? []

    readonly property int peakWatts: {
        let most = 0;
        for (const hour of hours)
            most = Math.max(most, hour.watts ?? 0);
        return Math.max(10, Math.ceil(most / 10) * 10);
    }

    readonly property var timeLabels: {
        const labels = [];
        for (let k = 0; history.start && k < 4; k++)
            labels.push({ at: k / 4, text: Qt.formatDateTime(new Date((history.start + k * 6 * 3600) * 1000), "h AP") });
        return labels;
    }

    Component.onCompleted: {
        if (Sys.Host.laptop)
            Sys.Power.readChargeLimit();
        if (Sys.Host.heater)
            Sys.Heater.refresh();
    }

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
            title: "Last 24 hours"
            visible: Sys.Power.present && root.levels.length > 0
            footnote: root.history.average_w ? "Averaging " + root.history.average_w.toFixed(1) + " W on battery." : ""

            Ui.Label {
                Layout.margins: Metrics.s3
                Layout.bottomMargin: 0
                text: "Battery level"
                role: "headline"
            }

            Ui.BarChart {
                Layout.fillWidth: true
                Layout.margins: Metrics.s3
                values: root.levels.map(level => level ? level.percent / 100 : null)
                tints: root.levels.map(level => level && !level.plugged && level.percent <= 20 ? Theme.critical : Theme.positive)
                shaded: root.levels.map(level => level?.plugged === true)
                yLabels: ["100%", "50%", "0%"]
                xLabels: root.timeLabels
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.Label {
                Layout.margins: Metrics.s3
                Layout.bottomMargin: 0
                text: "Energy use"
                role: "headline"
            }

            Ui.BarChart {
                Layout.fillWidth: true
                Layout.margins: Metrics.s3
                values: root.hours.map(hour => hour.watts === null ? null : hour.watts / root.peakWatts)
                yLabels: [root.peakWatts + " W", root.peakWatts / 2 + " W", "0 W"]
                xLabels: root.timeLabels
            }
        }

        Ui.Group {
            title: "App energy"
            visible: Sys.Power.present && root.apps.length > 0
            footnote: "Estimated from CPU and GPU time on battery, as a share of all battery energy."

            Repeater {
                model: root.apps.length

                Ui.ListRow {
                    id: app

                    required property int index
                    readonly property var entry: root.apps[app.index]

                    Layout.fillWidth: true
                    title: entry?.name ?? ""
                    subtitle: (entry?.wh ?? 0).toFixed(1) + " Wh"
                    interactive: false

                    RowLayout {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Metrics.s3

                        Ui.Meter {
                            fraction: (app.entry?.percent ?? 0) / 100
                        }

                        Ui.Label {
                            text: Math.round(app.entry?.percent ?? 0) + "%"
                            role: "caption"
                            numeric: true
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Metrics.s8
                        }
                    }
                }
            }
        }

        Ui.Group {
            title: "Performance"
            visible: Sys.Host.profileSwitching

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
            title: "Heater"
            visible: Sys.Host.heater
            footnote: "Mines Pearl on the GPU and Monero on every core."

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "flame"
                title: "Heater mode"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Heater.active
                    pending: Sys.Heater.busy
                    onToggled: enabled => Sys.Heater.set(enabled)
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
                visible: Sys.Host.laptop
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
