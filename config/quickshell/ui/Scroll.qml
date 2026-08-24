import QtQuick
import qs

// Wheel scrolling glides to a target instead of teleporting by a few pixels per
// notch, and the indicator is present only while it is telling you something.
// Both wheels reach it through the same glide `Choice` uses sideways, at the
// same step: two scroll speeds in one pane read as one of them being broken.
Flickable {
    id: root

    property bool indicator: true

    clip: true
    contentWidth: width
    boundsBehavior: Flickable.StopAtBounds
    pixelAligned: true

    property real _target: contentY

    readonly property real _limit: Math.max(0, contentHeight - height)

    function scrollBy(delta) {
        const from = glide.running ? _target : contentY;
        _target = Math.max(0, Math.min(_limit, from + delta));
        glide.to = _target;
        glide.restart();
    }

    NumberAnimation {
        id: glide
        target: root
        property: "contentY"
        duration: Motion.quick
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.enter
    }

    // The indicator answers "where am I", so it lives exactly as long as that
    // question does. Hover cannot drive it: rows accept hover themselves, so a
    // handler on the Flickable never sees the pointer once it is over content.
    property bool _recent: false

    onContentYChanged: {
        _recent = true;
        settle.restart();
    }

    Timer {
        id: settle
        interval: 900
        onTriggered: root._recent = false
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: event => {
            if (root._limit <= 0)
                return;
            root.scrollBy(-event.angleDelta.y / 120 * Metrics.wheelStep);
        }
    }

    Rectangle {
        // Caller content is appended after this, so without a z it paints over
        // the indicator.
        z: 10
        anchors.right: parent.right
        anchors.rightMargin: 2
        width: 3
        radius: width / 2
        color: Theme.textQuaternary
        visible: root.indicator && root._limit > 0
        opacity: root.moving || root._recent ? 0.85 : 0
        y: root.contentY + (root.contentY / Math.max(1, root._limit)) * (root.height - height)
        height: Math.max(28, root.height * (root.height / Math.max(1, root.contentHeight)))

        Behavior on opacity {
            Anim {
                duration: Motion.settled
            }
        }
    }
}
