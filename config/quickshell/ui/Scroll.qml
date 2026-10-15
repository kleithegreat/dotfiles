import QtQuick
import qs

// Wheel input glides to a target at the same step as `Choice`; see docs/quickshell.md.
Flickable {
    id: root

    property bool indicator: true

    clip: true
    contentWidth: width
    // The wheel bypasses Flickable's bounds; see docs/quickshell.md.
    boundsBehavior: Flickable.DragAndOvershootBounds
    pixelAligned: true

    WheelGlide {
        id: wheel
        flick: root
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

    Rectangle {
        // Caller content is appended after this, so without a z it paints over
        // the indicator.
        z: 10
        anchors.right: parent.right
        anchors.rightMargin: 2
        width: 3
        radius: width / 2
        color: Theme.textQuaternary
        visible: root.indicator && wheel.limit > 0
        opacity: root.moving || root._recent ? 0.85 : 0
        y: root.contentY + (root.contentY / Math.max(1, wheel.limit)) * (root.height - height)
        height: Math.max(28, root.height * (root.height / Math.max(1, root.contentHeight)))

        Behavior on opacity {
            Anim {
                duration: Motion.settled
            }
        }
    }
}
