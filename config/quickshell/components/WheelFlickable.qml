import QtQuick
import ".." as Root

Flickable {
    id: root

    property real wheelStep: Root.Theme.flickableWheelStep

    // Rubber-band overscroll tuning.
    property real _maxOvershoot: 56
    property real _dampFactor: 120
    property real _rawOverscroll: 0

    maximumFlickVelocity: 3000

    rebound: Transition {
        Anim {
            properties: "x,y"
        }
    }

    Timer {
        id: _returnTimer
        interval: 120
        onTriggered: {
            root._rawOverscroll = 0;
            root.returnToBounds();
        }
    }

    function _rubberBand(raw) {
        let absRaw = Math.abs(raw);
        if (absRaw < 0.5)
            return 0;
        return root._maxOvershoot * raw / (absRaw + root._dampFactor);
    }

    function applyWheelDelta(deltaY) {
        if (deltaY === 0)
            return false;

        let minY = root.originY;
        let maxY = Math.max(minY, root.originY + root.contentHeight - root.height);
        if (maxY <= minY)
            return false;

        // Reconstruct the virtual (unbounded) scroll position.
        let virtualY;
        if (root._rawOverscroll > 0)
            virtualY = maxY + root._rawOverscroll;
        else if (root._rawOverscroll < 0)
            virtualY = minY + root._rawOverscroll;
        else
            virtualY = root.contentY;

        let nextY = virtualY - deltaY;

        // Within bounds — normal 1:1 scroll.
        if (nextY >= minY && nextY <= maxY) {
            if (root._rawOverscroll !== 0) {
                root._rawOverscroll = 0;
                _returnTimer.stop();
            }
            if (Math.abs(nextY - root.contentY) < 0.01)
                return false;
            root.cancelFlick();
            root.contentY = nextY;
            return true;
        }

        // Past bounds — accumulate raw overscroll and apply rubber-band.
        root._rawOverscroll = nextY < minY ? nextY - minY : nextY - maxY;

        let bound = root._rawOverscroll < 0 ? minY : maxY;
        let visual = bound + root._rubberBand(root._rawOverscroll);

        if (Math.abs(visual - root.contentY) < 0.01)
            return false;

        root.cancelFlick();
        root.contentY = visual;
        _returnTimer.restart();

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
