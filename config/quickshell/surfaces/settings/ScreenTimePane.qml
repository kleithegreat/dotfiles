import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    readonly property int peak: {
        let most = 1;
        for (let i = 0; i < Sys.FocusTime.week.length; i++)
            most = Math.max(most, Sys.FocusTime.week[i].total);
        return most;
    }

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            title: Sys.FocusTime.weekRange
            footnote: Sys.FocusTime.stale ? "The focus tracker is not reporting." : ""

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Metrics.s3
                spacing: Metrics.s6

                ColumnLayout {
                    spacing: 0

                    Ui.Label {
                        text: Sys.FocusTime.format(Sys.FocusTime.today)
                        role: "title"
                        numeric: true
                    }

                    Ui.Label {
                        text: "Today"
                        role: "caption"
                    }
                }

                ColumnLayout {
                    spacing: 0

                    Ui.Label {
                        text: Sys.FocusTime.format(Sys.FocusTime.average)
                        role: "headline"
                        numeric: true
                        color: Theme.textSecondary
                    }

                    Ui.Label {
                        text: "Daily average"
                        role: "caption"
                    }
                }

                ColumnLayout {
                    spacing: 0

                    Ui.Label {
                        text: Sys.FocusTime.format(Sys.FocusTime.yesterday)
                        role: "headline"
                        numeric: true
                        color: Theme.textSecondary
                    }

                    Ui.Label {
                        text: "Yesterday"
                        role: "caption"
                    }
                }

                Item {
                    Layout.fillWidth: true
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Metrics.s3
                Layout.preferredHeight: 92
                spacing: Metrics.s2

                // Keyed on the count, never on the array: the tracker rewrites
                // its JSON every second, so binding the array itself destroys
                // and rebuilds every bar once a second — which is visible as
                // the whole chart replaying its grow animation on a heartbeat.
                Repeater {
                    model: Sys.FocusTime.week.length

                    ColumnLayout {
                        id: day

                        required property int index
                        readonly property var entry: Sys.FocusTime.week[day.index]

                        // Equal shares: fillWidth distributes only the surplus,
                        // so without a common base the columns inherit the
                        // differing widths of "Wed" and "Fri".
                        Layout.preferredWidth: 1
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Metrics.s1

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: Math.max(3, parent.height * ((day.entry?.total ?? 0) / root.peak))
                                radius: Metrics.s1
                                color: day.entry?.is_target ? Theme.accent : Theme.fillActive
                                antialiasing: true

                                Behavior on height {
                                    Ui.Anim {
                                        duration: Motion.settled
                                    }
                                }
                            }
                        }

                        Ui.Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: day.entry?.day ?? ""
                            role: "caption"
                            color: day.entry?.is_target ? Theme.text : Theme.textQuaternary
                        }
                    }
                }
            }
        }

        Ui.Group {
            title: "Most used"

            Repeater {
                model: Sys.FocusTime.apps.length

                Ui.ListRow {
                    id: app

                    required property int index
                    readonly property var modelData: Sys.FocusTime.apps[app.index]

                    Layout.fillWidth: true
                    title: modelData?.name ?? ""
                    subtitle: Sys.FocusTime.format(modelData?.seconds ?? 0)
                    interactive: false

                    RowLayout {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Metrics.s3

                        Rectangle {
                            width: 90
                            height: 5
                            radius: 2.5
                            color: Theme.fillTrack
                            antialiasing: true

                            Rectangle {
                                width: parent.width * Math.min(1, (app.modelData?.percent ?? 0) / 100)
                                height: parent.height
                                radius: parent.radius
                                color: Theme.accent
                                antialiasing: true
                            }
                        }

                        Ui.Label {
                            text: Math.round(app.modelData?.percent ?? 0) + "%"
                            role: "caption"
                            numeric: true
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Metrics.s8
                        }
                    }
                }
            }
        }
    }
}
