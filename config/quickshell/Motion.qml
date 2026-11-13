pragma Singleton

import QtQuick

// Material 3's expressive motion tokens. Pick by intent, not by feel.
QtObject {
    // A state flip the pointer is already committed to — hover, press, toggle.
    readonly property int instant: 150
    // The default: anything the eye should follow, and every exit.
    readonly property int quick: 250
    // Surfaces arriving, content re-laying out.
    readonly property int settled: 450

    // Easing.BezierSpline control points: [cx1, cy1, cx2, cy2, 1, 1]

    // Colour and opacity.
    readonly property var standard: [0.2, 0.0, 0.0, 1.0, 1.0, 1.0]
    // Travel that must land exactly: scrolling, a panel resizing to its content.
    readonly property var enter: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
    // Gets out of the way. Exits are never as slow as entrances.
    readonly property var exit: [0.3, 0.0, 0.8, 0.15, 1.0, 1.0]
    // Arriving in place with a slight overshoot: surfaces, switches, pills.
    // Position and scale only; on opacity it clamps and reads as a pop.
    readonly property var spring: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0]

    // Surfaces grow from the control that summoned them, not from their own
    // centre; the scale start is small enough to read as motion and large enough
    // not to read as a zoom.
    readonly property real emergeScale: 0.94
}
