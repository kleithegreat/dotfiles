import QtQuick
import qs

// A square hit target holding one icon. `filled` is the primary-action look: a resting fill rather than none.
Pressable {
    id: root

    property string name
    property color iconColor: Theme.textTertiary
    property int iconSize: Metrics.iconSm
    property int size: Metrics.s6
    property bool filled: false

    implicitWidth: size
    implicitHeight: size
    showFill: !filled

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        visible: root.filled
        color: root.pressed ? Theme.fillPress : root.hovered ? Theme.fillActive : Theme.fillTrack
        antialiasing: true

        Behavior on color {
            Tint {}
        }
    }

    Icon {
        anchors.centerIn: parent
        name: root.name
        size: root.iconSize
        color: root.iconColor
    }
}
