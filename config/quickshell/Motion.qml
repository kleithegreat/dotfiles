pragma Singleton

import QtQuick

// Four durations and three curves. The old shell had twenty durations, which is
// the same as having none: nothing could be recognised as belonging to the same
// system. Pick by intent, not by feel.
QtObject {
    // A state flip the pointer is already committed to — hover, press, toggle.
    readonly property int instant: 110
    // The default: anything the eye should follow.
    readonly property int quick: 180
    // Surfaces arriving or leaving, content re-laying out.
    readonly property int settled: 260
    // Showpiece entrances only.
    readonly property int deliberate: 340

    // Easing.BezierSpline control points: [cx1, cy1, cx2, cy2, 1, 1]

    // Symmetric; for continuous properties like colour and opacity.
    readonly property var standard: [0.32, 0.06, 0.2, 1.0, 1.0, 1.0]
    // Leaves immediately, lands softly. Entrances and anything travelling.
    readonly property var enter: [0.16, 1.0, 0.3, 1.0, 1.0, 1.0]
    // Gets out of the way. Exits are never as slow as entrances.
    readonly property var exit: [0.4, 0.0, 0.9, 0.5, 1.0, 1.0]

    // Surfaces grow from the control that summoned them, not from their own
    // centre; the scale start is small enough to read as motion and large enough
    // not to read as a zoom.
    readonly property real emergeScale: 0.94
}
