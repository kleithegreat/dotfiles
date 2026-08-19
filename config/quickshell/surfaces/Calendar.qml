import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.ui as Ui
import qs.services as Sys

Popover {
    id: root

    required property ShellState state

    shown: state.isOpen("calendar")
    anchor: state.anchor
    panelWidth: cell * 7 + Metrics.panelInset * 2
    contentHeight: month.implicitHeight

    readonly property int cell: 36

    property int offset: 0

    onShownChanged: {
        if (shown) {
            offset = 0;
            Sys.Weather.refresh(false);
        }
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    readonly property date today: clock.date
    readonly property date shown_: new Date(today.getFullYear(), today.getMonth() + offset, 1)
    readonly property int firstWeekday: shown_.getDay()
    readonly property int daysInMonth: new Date(shown_.getFullYear(), shown_.getMonth() + 1, 0).getDate()
    readonly property bool isThisMonth: offset === 0

    ColumnLayout {
        id: month
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Metrics.s2

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Ui.Label {
                text: Qt.formatDateTime(root.shown_, "MMMM yyyy")
                role: "headline"
                Layout.fillWidth: true
            }

            Ui.Pressable {
                implicitWidth: Metrics.s6
                implicitHeight: Metrics.s6
                onClicked: root.offset--

                Ui.Icon {
                    anchors.centerIn: parent
                    name: "chevron-left"
                    size: Metrics.iconSm
                    color: Theme.textTertiary
                }
            }

            Ui.Pressable {
                implicitWidth: Metrics.s6
                implicitHeight: Metrics.s6
                onClicked: root.offset++

                Ui.Icon {
                    anchors.centerIn: parent
                    name: "chevron-right"
                    size: Metrics.iconSm
                    color: Theme.textTertiary
                }
            }
        }

        Grid {
            Layout.fillWidth: true
            columns: 7

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]

                Item {
                    required property string modelData
                    width: root.cell
                    height: Metrics.s5

                    Ui.Label {
                        anchors.centerIn: parent
                        text: parent.modelData
                        role: "section"
                        color: Theme.textQuaternary
                    }
                }
            }

            Repeater {
                model: root.firstWeekday + root.daysInMonth

                Item {
                    id: slot

                    required property int index
                    readonly property int day: slot.index - root.firstWeekday + 1
                    readonly property bool filled: slot.day >= 1
                    readonly property bool isToday: root.isThisMonth && slot.day === root.today.getDate()

                    width: root.cell
                    height: root.cell

                    Rectangle {
                        anchors.centerIn: parent
                        width: Metrics.s6 + Metrics.s1
                        height: width
                        radius: width / 2
                        color: Theme.accent
                        visible: slot.isToday
                        antialiasing: true
                    }

                    Ui.Label {
                        anchors.centerIn: parent
                        visible: slot.filled
                        text: slot.day
                        role: "callout"
                        numeric: true
                        font.weight: slot.isToday ? Theme.weightSemi : Theme.weightRegular
                        color: slot.isToday ? Theme.onAccent : Theme.textSecondary
                    }
                }
            }
        }

        Ui.Divider {}

        // Weather is a second widget stacked under the month, not a tab beside
        // it: a switch between "the days of this month" and "it is 31 degrees"
        // makes the reader choose between two things they wanted to see at once.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Metrics.s1
            spacing: Metrics.s3

            ColumnLayout {
                spacing: 0

                Ui.Label {
                    text: Sys.Weather.ready ? Math.round(Sys.Weather.temperature) + Sys.Weather.unit : Sys.Weather.loading ? "··" : "--"
                    role: "title"
                    numeric: true
                }

                Ui.Label {
                    text: Sys.Weather.ready ? Sys.Weather.conditions : Sys.Weather.error !== "" ? Sys.Weather.error : "Loading"
                    role: "caption"
                }
            }

            Item {
                Layout.fillWidth: true
            }

            ColumnLayout {
                spacing: 0
                visible: Sys.Weather.ready

                Ui.Label {
                    text: Math.round(Sys.Weather.high) + "° / " + Math.round(Sys.Weather.low) + "°"
                    role: "callout"
                    numeric: true
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                }

                Ui.Label {
                    text: Sys.Weather.rainChance + "% rain · " + Sys.Weather.sunset
                    role: "caption"
                    numeric: true
                    horizontalAlignment: Text.AlignRight
                    Layout.fillWidth: true
                }
            }
        }
    }
}
