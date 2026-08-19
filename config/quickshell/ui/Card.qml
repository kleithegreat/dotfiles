import QtQuick
import qs

// Dense content sits on an opaque card inside a glass panel. Stacking
// translucency on translucency is what makes a shell look muddy.
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
