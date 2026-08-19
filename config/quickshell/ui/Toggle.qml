import QtQuick
import qs

Pressable {
    id: root

    property bool checked: false
    // A write that has been sent but not confirmed by the backend. The control
    // shows the value it will have, dimmed, rather than snapping back.
    property bool pending: false

    signal toggled(bool value)

    implicitWidth: Metrics.toggleWidth
    implicitHeight: Metrics.toggleHeight
    radius: Metrics.rPill
    showFill: false
    pressScale: 0.94
    opacity: !interactive ? 0.4 : pending ? 0.65 : 1.0

    onClicked: root.toggled(!root.checked)

    Behavior on opacity {
        Anim {}
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : Theme.fillTrack
        antialiasing: true

        Behavior on color {
            Tint {
                duration: Motion.quick
            }
        }

        Rectangle {
            id: knob
            y: (parent.height - height) / 2
            x: root.checked ? parent.width - width - (parent.height - height) / 2 : (parent.height - height) / 2
            width: Metrics.toggleKnob
            height: Metrics.toggleKnob
            radius: height / 2
            color: Qt.rgba(1, 1, 1, 0.97)
            antialiasing: true

            Behavior on x {
                Anim {
                    duration: Motion.quick
                    easing.bezierCurve: Motion.enter
                }
            }
        }
    }
}
