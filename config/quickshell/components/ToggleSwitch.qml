import QtQuick
import ".." as Root

Item {
    id: toggle

    property bool checked: false
    property bool disabled: false
    property bool pending: false
    signal toggled()

    width: Root.Theme.toggleWidth
    height: Root.Theme.toggleHeight
    activeFocusOnTab: true

    Keys.onPressed: (event) => {
        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                && !toggle.disabled && !toggle.pending) {
            toggle.toggled();
            event.accepted = true;
        }
    }

    opacity: toggle.disabled ? 0.45 : (toggle.pending ? 0.7 : 1)
    Behavior on opacity { NumberAnimation { duration: Root.Theme.animHover } }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -3
        radius: height / 2
        color: "transparent"
        border.width: toggle.activeFocus ? 2 : 0
        border.color: Root.Theme.blueBright
        opacity: toggle.activeFocus ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Root.Theme.animHover } }
    }

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
        anchors.fill: parent
        enabled: !toggle.disabled && !toggle.pending
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            toggle.forceActiveFocus();
            toggle.toggled();
        }
    }
}
