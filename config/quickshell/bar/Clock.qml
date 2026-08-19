import QtQuick
import Quickshell
import qs
import qs.ui as Ui

BarItem {
    id: root

    contentWidth: line.width

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Row {
        id: line
        anchors.centerIn: parent
        spacing: Metrics.s2

        Ui.Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "ddd d MMM")
            role: "callout"
            color: root.hovered ? Theme.textSecondary : Theme.textTertiary
        }

        Ui.Label {
            anchors.verticalCenter: parent.verticalCenter
            text: Qt.formatDateTime(clock.date, "h:mm AP")
            role: "callout"
            numeric: true
            font.weight: Theme.weightMedium
        }
    }
}
