import QtQuick
import ".." as Root

Flickable {
    id: root

    property real wheelStep: Root.Theme.flickableWheelStep

    function applyWheelDelta(deltaY) {
        if (deltaY === 0)
            return false;

        let minY = root.originY;
        let maxY = Math.max(minY, root.originY + root.contentHeight - root.height);
        let nextY = Math.max(minY, Math.min(root.contentY - deltaY, maxY));
        if (nextY === root.contentY)
            return false;

        root.contentY = nextY;
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
