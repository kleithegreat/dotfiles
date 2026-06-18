import QtQuick
import QtQuick.Layouts
import ".." as Root

// Shared horizontal value slider: filled bar + draggable knob + pointer input.
// Callers bind `fraction` (0..1) and react to `moved(fraction)`, emitted on
// press and drag. `pressStarted`/`pressEnded` let callers gate side effects
// (OSD suppression, commit-on-release) around an interaction.
Rectangle {
    id: track

    property real fraction: 0
    property color fillColor: Root.Theme.greenBright
    property int knobSize: Root.Theme.sliderKnobSize
    property bool disabled: false

    signal moved(real fraction)
    signal pressStarted()
    signal pressEnded()

    readonly property real _clamped: Math.max(0, Math.min(1, track.fraction))

    function _emit(x) {
        track.moved(Math.max(0, Math.min(1, x / track.width)));
    }

    Layout.fillWidth: true
    height: Root.Theme.sliderHeight
    radius: Root.Theme.sliderHeight / 2
    color: Root.Theme.bg3

    Rectangle {
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: parent.width * track._clamped
        radius: parent.radius
        color: track.fillColor
        Behavior on width {
            Anim {
                duration: Root.Theme.animMicro
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Root.Theme.animCurveStandard
            }
        }
    }

    Rectangle {
        width: track.knobSize
        height: track.knobSize
        radius: width / 2
        color: Root.Theme.fg
        y: (parent.height - height) / 2
        x: Math.max(0, Math.min(parent.width - width, parent.width * track._clamped - width / 2))
        scale: area.pressed ? 1.2 : (area.containsMouse ? 1.1 : 1.0)
        Behavior on scale {
            Anim {
                duration: Root.Theme.animMicro
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Root.Theme.animCurveStandard
            }
        }
        Behavior on x { SpringAnimation { spring: Root.Theme.sliderSpring; damping: Root.Theme.sliderDamping } }
    }

    HoverLayer {
        id: area
        disabled: track.disabled
        hoverOpacity: 0
        pressedOpacity: 0
        pressedScale: 1.0
        onPressed: (mouse) => { track.pressStarted(); track._emit(mouse.x); }
        onPositionChanged: (mouse) => { if (pressed) track._emit(mouse.x); }
        onReleased: track.pressEnded()
    }
}
