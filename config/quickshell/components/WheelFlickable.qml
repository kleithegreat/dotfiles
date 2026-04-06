import QtQuick
import ".." as Root

Flickable {
    id: root

    property real wheelStep: Root.Theme.flickableWheelStep

    // Rubber-band overscroll tuning.
    property real _maxOvershoot: 56
    property real _dampFactor: 120
    property real _rawOverscroll: 0
    property bool _isTrackpad: false

    maximumFlickVelocity: 3000

    rebound: Transition {
        Anim {
            properties: "x,y"
        }
    }

    Timer {
        id: _returnTimer
        // Trackpad events come in rapid bursts; use a longer idle timeout
        // to avoid firing mid-gesture and starting a rebound too early.
        interval: root._isTrackpad ? 200 : 120
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

    // Invert the rubber-band function: given a visual displacement,
    // recover the unbounded (raw) overscroll distance.
    function _invertRubberBand(visual) {
        let absV = Math.abs(visual);
        if (absV < 0.5)
            return 0;
        let absRaw = absV * root._dampFactor / (root._maxOvershoot - absV);
        return visual < 0 ? -absRaw : absRaw;
    }

    function applyWheelDelta(deltaY) {
        if (deltaY === 0)
            return false;

        let minY = root.originY;
        let maxY = Math.max(minY, root.originY + root.contentHeight - root.height);
        if (maxY <= minY)
            return false;

        // If the return timer already fired and a rebound animation is in
        // progress, _rawOverscroll was reset to 0 but contentY is still
        // out of bounds (mid-animation).  Recover the true overscroll state
        // from the current visual position so we can continue smoothly.
        if (root._rawOverscroll === 0) {
            let cY = root.contentY;
            if (cY < minY)
                root._rawOverscroll = root._invertRubberBand(cY - minY);
            else if (cY > maxY)
                root._rawOverscroll = root._invertRubberBand(cY - maxY);
        }

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
            root._isTrackpad = event.pixelDelta.y !== 0;

            // Touchpads already report pixel distances; notch wheels need a theme-tuned step.
            let deltaY = event.pixelDelta.y;
            if (deltaY === 0)
                deltaY = event.angleDelta.y / 120 * root.wheelStep;

            event.accepted = root.applyWheelDelta(deltaY);
        }
    }
}
