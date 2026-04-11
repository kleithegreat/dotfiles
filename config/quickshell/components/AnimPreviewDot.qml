import QtQuick
import ".." as Root

Canvas {
    id: root

    property real x1: 0.25
    property real y1: 0.1
    property real x2: 0.25
    property real y2: 1.0

    implicitHeight: 32
    implicitWidth: 200

    property real _progress: 0
    property bool _waiting: false

    function _cubicBezier(t, p1, p2) {
        return 3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t;
    }

    function _solveT(x, cx1, cx2) {
        let t = x;
        for (let i = 0; i < 20; i++) {
            let xAtT = _cubicBezier(t, cx1, cx2);
            let dx = 3 * (1 - t) * (1 - t) * cx1 + 6 * (1 - t) * t * (cx2 - cx1) + 3 * t * t * (1 - cx2);
            if (Math.abs(dx) < 1e-6) break;
            t -= (xAtT - x) / dx;
            t = Math.max(0, Math.min(1, t));
        }
        return t;
    }

    function ease(progress) {
        let t = _solveT(progress, x1, x2);
        return _cubicBezier(t, y1, y2);
    }

    readonly property var _bounds: {
        let lo = 0.0; let hi = 1.0;
        for (let i = 0; i <= 100; i++) {
            let v = ease(i / 100);
            if (v < lo) lo = v;
            if (v > hi) hi = v;
        }
        return { lo: lo, hi: hi };
    }

    Timer {
        interval: 16; running: root.visible; repeat: true
        onTriggered: {
            if (root._waiting) return;
            root._progress += 0.012;
            if (root._progress >= 1.0) {
                root._progress = 1.0;
                root._waiting = true;
                pauseTimer.restart();
            }
            root.requestPaint();
        }
    }

    Timer {
        id: pauseTimer; interval: 1000
        onTriggered: { root._progress = 0; root._waiting = false; root.requestPaint(); }
    }

    function _c(color, alpha) {
        return "rgba(" + Math.round(color.r * 255) + "," + Math.round(color.g * 255)
            + "," + Math.round(color.b * 255) + "," + alpha + ")";
    }

    onPaint: {
        let ctx = getContext("2d");
        ctx.reset();

        let w = width; let h = height;
        let fg = Root.Theme.fg;
        let accent = Root.Theme.accent;
        let bounds = _bounds;
        let span = bounds.hi - bounds.lo;
        if (span < 0.01) span = 1;
        let dotR = 5; let pad = dotR + 2;
        let usable = w - 2 * pad;
        let trackY = h / 2;

        function valToX(v) { return pad + (v - bounds.lo) / span * usable; }

        // Undershoot track
        if (bounds.lo < 0) {
            ctx.setLineDash([4, 4]); ctx.strokeStyle = _c(fg, 0.15); ctx.lineWidth = 2;
            ctx.beginPath(); ctx.moveTo(valToX(bounds.lo), trackY); ctx.lineTo(valToX(0), trackY); ctx.stroke();
            ctx.setLineDash([]);
        }

        // Main track [0,1]
        ctx.strokeStyle = _c(fg, 0.25); ctx.lineWidth = 2;
        ctx.beginPath(); ctx.moveTo(valToX(0), trackY); ctx.lineTo(valToX(1), trackY); ctx.stroke();

        // Overshoot track
        if (bounds.hi > 1) {
            ctx.setLineDash([4, 4]); ctx.strokeStyle = _c(fg, 0.15); ctx.lineWidth = 2;
            ctx.beginPath(); ctx.moveTo(valToX(1), trackY); ctx.lineTo(valToX(bounds.hi), trackY); ctx.stroke();
            ctx.setLineDash([]);
        }

        // Endpoints
        ctx.fillStyle = _c(fg, 0.25);
        ctx.beginPath(); ctx.arc(valToX(0), trackY, 2.5, 0, 2 * Math.PI); ctx.fill();
        ctx.beginPath(); ctx.arc(valToX(1), trackY, 2.5, 0, 2 * Math.PI); ctx.fill();

        // Dot
        let eased = ease(_progress);
        ctx.fillStyle = _c(accent, 1.0);
        ctx.beginPath(); ctx.arc(valToX(eased), trackY, dotR, 0, 2 * Math.PI); ctx.fill();
    }

    onX1Changed: requestPaint()
    onY1Changed: requestPaint()
    onX2Changed: requestPaint()
    onY2Changed: requestPaint()
}
