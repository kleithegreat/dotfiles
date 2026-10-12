import QtQuick
import qs

// A read-only fraction. Not a `Slider`: no knob, no input.
Rectangle {
    id: root

    property real fraction: 0
    property color fill: Theme.accent

    implicitWidth: 90
    implicitHeight: Metrics.trackHeight
    radius: height / 2
    color: Theme.fillTrack
    antialiasing: true

    Rectangle {
        width: root.width * Math.max(0, Math.min(1, root.fraction))
        height: parent.height
        radius: parent.radius
        color: root.fill
        antialiasing: true

        Behavior on width {
            Anim {
                duration: Motion.instant
            }
        }
    }
}
