import QtQuick
import qs

Row {
    id: root

    property int value: 0
    required property int minimum
    required property int maximum

    signal changed(int value)

    spacing: Metrics.s1

    function nudge(delta) {
        const next = Math.max(minimum, Math.min(maximum, value + delta));
        if (next !== value)
            root.changed(next);
    }

    Pressable {
        implicitWidth: Metrics.s6
        implicitHeight: Metrics.controlHeight
        interactive: root.value > root.minimum
        onClicked: root.nudge(-1)

        Label {
            anchors.centerIn: parent
            text: "−"
            role: "body"
            color: Theme.textSecondary
        }
    }

    Label {
        anchors.verticalCenter: parent.verticalCenter
        width: Metrics.s8
        text: root.value
        role: "callout"
        numeric: true
        horizontalAlignment: Text.AlignHCenter
    }

    Pressable {
        implicitWidth: Metrics.s6
        implicitHeight: Metrics.controlHeight
        interactive: root.value < root.maximum
        onClicked: root.nudge(1)

        Label {
            anchors.centerIn: parent
            text: "+"
            role: "body"
            color: Theme.textSecondary
        }
    }
}
