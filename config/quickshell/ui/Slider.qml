import QtQuick
import qs

// Continuous value control. `moved` fires throughout the gesture for live
// preview; `committed` fires once at the end, for backends that should not be
// driven at pointer rate.
Item {
    id: root

    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 0.05
    property bool interactive: true
    property bool pending: false
    // Set on sliders that live inside a scroll view: Flickable steals the grab
    // once a drag passes threshold, which silently reduces the slider to
    // click-to-set.
    property bool claimsDrag: true

    readonly property alias pressed: pointer.pressed

    signal moved(real value)
    signal committed(real value)

    implicitHeight: Math.max(Metrics.knob, Metrics.controlHeight)
    implicitWidth: 120
    opacity: interactive ? (pending ? Theme.pendingAlpha : 1.0) : 0.4

    readonly property real _span: Math.max(0.0001, maximum - minimum)
    property bool _dragging: false
    property real _local: 0
    // What the control displays: the caller's value, or the drag in progress.
    readonly property real shown: _dragging ? _local : value
    readonly property real _fraction: Math.max(0, Math.min(1, (shown - minimum) / _span))
    readonly property real _usable: width - Metrics.knob

    function _valueAt(px) {
        const f = Math.max(0, Math.min(1, (px - Metrics.knob / 2) / Math.max(1, _usable)));
        return minimum + f * _span;
    }

    Behavior on opacity {
        Anim {}
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        height: Metrics.trackHeight
        radius: height / 2
        color: Theme.fillTrack
        antialiasing: true

        Rectangle {
            width: Math.max(height, Metrics.knob / 2 + root._fraction * root._usable)
            height: parent.height
            radius: parent.radius
            color: Theme.text
            antialiasing: true

            Behavior on width {
                enabled: !pointer.pressed
                Anim {
                    duration: Motion.instant
                }
            }
        }
    }

    Rectangle {
        x: root._fraction * root._usable
        anchors.verticalCenter: parent.verticalCenter
        width: Metrics.knob
        height: Metrics.knob
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.98)
        scale: pointer.pressed ? 1.12 : pointer.containsMouse ? 1.06 : 1.0
        antialiasing: true

        Behavior on x {
            enabled: !pointer.pressed
            Anim {
                duration: Motion.instant
            }
        }

        Behavior on scale {
            Anim {
                duration: Motion.instant
            }
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        anchors.margins: -Metrics.s1
        enabled: root.interactive
        hoverEnabled: true
        preventStealing: root.claimsDrag
        cursorShape: Qt.PointingHandCursor

        function apply(px) {
            root._local = root._valueAt(px);
            root._dragging = true;
            root.moved(root._local);
        }

        onPressed: mouse => apply(mouse.x)
        onPositionChanged: mouse => {
            if (pressed)
                apply(mouse.x);
        }
        onReleased: {
            root.committed(root._local);
            root._dragging = false;
        }
        onCanceled: root._dragging = false

        onWheel: event => {
            const delta = event.angleDelta.y > 0 ? root.step : -root.step;
            const next = Math.max(root.minimum, Math.min(root.maximum, root.shown + delta * root._span));
            root.moved(next);
            root.committed(next);
        }
    }
}
