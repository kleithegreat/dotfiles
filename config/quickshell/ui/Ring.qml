import QtQuick
import QtQuick.Shapes
import qs

// A circular gauge filling clockwise from twelve o'clock, or, while `busy`, a
// short arc circling for work with no measure yet.
Item {
    id: root

    property real fraction: 0
    property bool busy: false
    property color color: Theme.accent
    property color track: Theme.fillTrack
    property real thickness: 3

    implicitWidth: 44
    implicitHeight: 44

    // A measured arc starts at twelve, wherever the spinner stopped.
    onBusyChanged: {
        if (!busy)
            shape.rotation = 0;
    }

    property real _sweep: busy ? 0.25 : Math.max(0, Math.min(1, fraction))
    Behavior on _sweep {
        Anim {
            duration: Motion.settled
            easing.bezierCurve: Motion.enter
        }
    }

    Shape {
        id: shape

        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        readonly property real radius: (Math.min(width, height) - root.thickness) / 2

        ShapePath {
            fillColor: "transparent"
            strokeColor: root.track
            strokeWidth: root.thickness

            PathAngleArc {
                centerX: shape.width / 2
                centerY: shape.height / 2
                radiusX: shape.radius
                radiusY: shape.radius
                startAngle: 0
                sweepAngle: 360
            }
        }

        ShapePath {
            fillColor: "transparent"
            strokeColor: root._sweep > 0 ? root.color : "transparent"
            strokeWidth: root.thickness
            capStyle: ShapePath.RoundCap

            PathAngleArc {
                centerX: shape.width / 2
                centerY: shape.height / 2
                radiusX: shape.radius
                radiusY: shape.radius
                startAngle: -90
                sweepAngle: 360 * root._sweep
            }
        }

        RotationAnimator on rotation {
            running: root.busy && root.visible
            from: 0
            to: 360
            duration: 1100
            loops: Animation.Infinite
        }
    }
}
