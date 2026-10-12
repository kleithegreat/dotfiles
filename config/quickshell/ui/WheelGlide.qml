import QtQuick
import qs

// Wheel input glides `flick` along one axis, stretching past an edge by hand; see docs/quickshell.md.
Item {
    id: root

    required property Flickable flick
    property bool horizontal: false
    property bool active: true

    readonly property bool running: glide.running
    readonly property real limit: horizontal ? Math.max(0, flick.contentWidth - flick.width) : Math.max(0, flick.contentHeight - flick.height)

    anchors.fill: parent

    function scrollTo(position, curve) {
        glide.to = position;
        glide.easing.bezierCurve = curve || Motion.enter;
        glide.restart();
    }

    function scrollBy(delta) {
        const next = (glide.running ? glide.to : horizontal ? flick.contentX : flick.contentY) + delta;
        const past = next < 0 ? -next : next > limit ? next - limit : 0;

        if (past === 0) {
            scrollTo(next);
            return;
        }

        scrollTo(next < 0 ? -Metrics.resist(past) : limit + Metrics.resist(past));
        recoil.restart();
    }

    // Springs back once the input stops; holding against the end stays stretched.
    Timer {
        id: recoil
        interval: Motion.instant
        onTriggered: root.scrollTo(Math.max(0, Math.min(root.limit, glide.to)), Motion.standard)
    }

    NumberAnimation {
        id: glide
        target: root.flick
        property: root.horizontal ? "contentX" : "contentY"
        duration: Motion.quick
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.enter
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.active && root.limit > 0
        onWheel: event => {
            const delta = root.horizontal && event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
            root.scrollBy(-delta / 120 * Metrics.wheelStep);
        }
    }
}
