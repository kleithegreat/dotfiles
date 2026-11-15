import QtQuick
import qs

Rectangle {
    radius: Metrics.rCard
    color: Theme.raised
    border.width: Metrics.hairline
    border.color: Theme.separator
    antialiasing: true

    Behavior on color {
        Tint {
            duration: Motion.quick
        }
    }
}
