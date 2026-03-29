import QtQuick
import ".." as Root

Flickable {
    id: root

    property real wheelStep: Root.Theme.flickableWheelStep
    property real wheelOvershoot: Math.max(24, Math.min(48, wheelStep / 2))

    maximumFlickVelocity: 3000

    rebound: Transition {
        Anim {
            properties: "x,y"
        }
    }

    function applyWheelDelta(deltaY) {
        if (deltaY === 0)
            return false;

        let minY = root.originY;
        let maxY = Math.max(minY, root.originY + root.contentHeight - root.height);
        if (maxY <= minY)
            return false;

        let nextY = root.contentY - deltaY;
        let overshooting = false;

        // Allow a small wheel overshoot so Flickable.rebound can animate the snap-back.
        if (nextY < minY) {
            nextY = Math.max(minY - root.wheelOvershoot, nextY);
            overshooting = true;
        } else if (nextY > maxY) {
            nextY = Math.min(maxY + root.wheelOvershoot, nextY);
            overshooting = true;
        }

        if (Math.abs(nextY - root.contentY) < 0.01)
            return false;

        root.cancelFlick();
        root.contentY = nextY;

        if (overshooting)
            root.returnToBounds();

        return true;
    }

    WheelHandler {
        target: null
        orientation: Qt.Vertical
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        blocking: false

        onWheel: function(event) {
            // Touchpads already report pixel distances; notch wheels need a theme-tuned step.
            let deltaY = event.pixelDelta.y;
            if (deltaY === 0)
                deltaY = event.angleDelta.y / 120 * root.wheelStep;

            event.accepted = root.applyWheelDelta(deltaY);
        }
    }
}
