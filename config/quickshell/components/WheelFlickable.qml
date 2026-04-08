import QtQuick
import ".." as Root

Flickable {
    id: root

    property real wheelStep: Root.Theme.flickableWheelStep
    property real overshootDamping: 0.32

    boundsMovement: Flickable.FollowBoundsBehavior
    boundsBehavior: Flickable.DragAndOvershootBounds
    maximumFlickVelocity: 3000

    rebound: Transition {
        Anim {
            properties: "x,y"
        }
    }

    function minimumContentY() {
        return root.originY;
    }

    function maximumContentY() {
        return Math.max(root.minimumContentY(), root.originY + root.contentHeight - root.height);
    }

    function hasVerticalOverflow() {
        return root.maximumContentY() - root.minimumContentY() > 0.5;
    }

    function applyWheelDelta(deltaY) {
        if (deltaY === 0 || !root.hasVerticalOverflow())
            return false;

        let minY = root.minimumContentY();
        let maxY = root.maximumContentY();
        let nextY = root.contentY - deltaY;

        let clampedY = nextY;
        if (clampedY < minY)
            clampedY = minY + (clampedY - minY) * root.overshootDamping;
        else if (clampedY > maxY)
            clampedY = maxY + (clampedY - maxY) * root.overshootDamping;

        if (Math.abs(clampedY - root.contentY) < 0.01)
            return false;

        root.cancelFlick();
        root.contentY = clampedY;
        return true;
    }

    WheelHandler {
        target: null
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: false

        onActiveChanged: {
            if (!active)
                root.returnToBounds();
        }

        onWheel: function(event) {
            let deltaY = event.pixelDelta.y;
            if (deltaY === 0)
                deltaY = event.angleDelta.y / 120 * root.wheelStep;

            event.accepted = root.applyWheelDelta(deltaY);
        }
    }
}
