import QtQuick
import qs

// Dense content sits on a raised card inside a panel, so a list or a grid
// reads as one block lifted off the panel's own ground.
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
