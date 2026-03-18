import QtQuick
import ".." as Root

Item {
    id: toggle

    property bool checked: false
    signal toggled()

    width: Root.Theme.toggleWidth
    height: Root.Theme.toggleHeight

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: toggle.checked ? Root.Theme.greenBright : Root.Theme.bg3
        Behavior on color { ColorAnimation { duration: Root.Theme.animSpring } }

        Rectangle {
            id: knob
            width: Root.Theme.toggleKnobSize; height: Root.Theme.toggleKnobSize
            radius: width / 2; y: (parent.height - height) / 2
            x: toggle.checked ? parent.width - width - (parent.height - height) / 2 : (parent.height - height) / 2
            color: Root.Theme.fg

            scale: knobMouse.pressed ? 1.1 : 1.0
            Behavior on scale { NumberAnimation { duration: Root.Theme.animMicro; easing.type: Easing.OutCubic } }
            Behavior on x { NumberAnimation { duration: Root.Theme.animSpring; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }
        }
    }

    MouseArea {
        id: knobMouse
        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
        onClicked: toggle.toggled()
    }
}
