import QtQuick
import qs

// Direction comes from this Behavior's own target ([[quickshell]]).
Behavior {
    id: root

    // What the property holds while the surface is shown.
    required property real shownValue
    property int enterDuration: Motion.settled
    property int exitDuration: Motion.quick
    property var enterCurve: Motion.spring
    property var exitCurve: Motion.exit
    // Holds an entrance back so a part follows what it sits on. Exits never wait.
    property int enterDelay: 0

    readonly property bool arriving: targetValue === shownValue
    readonly property alias running: sequence.running

    SequentialAnimation {
        id: sequence

        PauseAnimation {
            duration: root.arriving ? root.enterDelay : 0
        }
        Anim {
            duration: root.arriving ? root.enterDuration : root.exitDuration
            easing.bezierCurve: root.arriving ? root.enterCurve : root.exitCurve
        }
    }
}
