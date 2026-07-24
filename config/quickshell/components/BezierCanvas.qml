import QtQuick
import ".." as Root

Canvas {
    id: root

    property real x1: 0.25
    property real y1: 0.1
    property real x2: 0.25
    property real y2: 1.0

    signal pointsChanged(real x1, real y1, real x2, real y2)

    property string _dragging: ""
    property real _dragScale: 1.0
    property real _dragStartX: 0
    property real _dragStartY: 0
    property real _dragOriginBx: 0
    property real _dragOriginBy: 0
    property real _viewYLo: -0.1
    property real _viewYHi: 1.1

    readonly property int _pad: 24
    readonly property int _handleRadius: 8

    function setPoints(nx1, ny1, nx2, ny2) {
        x1 = nx1; y1 = ny1; x2 = nx2; y2 = ny2;
        _updateViewRange();
        requestPaint();
    }

    function _cubicBezier(t, p1, p2) {
        return 3 * (1 - t) * (1 - t) * t * p1 + 3 * (1 - t) * t * t * p2 + t * t * t;
    }

    function _gridMetrics() {
        let w = width; let h = height;
        let yLo = _viewYLo; let yHi = _viewYHi;
        let ySpan = yHi - yLo;
        let sX = (w - 2 * _pad) / 1.0;
        let sY = (h - 2 * _pad) / ySpan;
        let s = Math.min(sX, sY);
        let dW = 1.0 * s; let dH = ySpan * s;
        return { scale: s, xOff: (w - dW) / 2, yOff: (h - dH) / 2, yLo: yLo, yHi: yHi };
    }

    function _toCanvas(bx, by) {
        let m = _gridMetrics();
        return { x: m.xOff + bx * m.scale, y: m.yOff + (m.yHi - by) * m.scale };
    }

    function _hitTest(cx, cy) {
        let p1 = _toCanvas(x1, y1);
        let p2 = _toCanvas(x2, y2);
        let r2 = (_handleRadius + 4) * (_handleRadius + 4);
        if ((cx - p1.x) * (cx - p1.x) + (cy - p1.y) * (cy - p1.y) <= r2) return "p1";
        if ((cx - p2.x) * (cx - p2.x) + (cy - p2.y) * (cy - p2.y) <= r2) return "p2";
        return "";
    }

    function _updateViewRange() {
        let margin = 0.1;
        _viewYLo = Math.min(0.0, y1, y2) - margin;
        _viewYHi = Math.max(1.0, y1, y2) + margin;
    }

    onPaint: {
        let ctx = getContext("2d");
        ctx.reset();

        let fg = Root.Theme.fg;
        let accent = Root.Theme.accent;

        let g0 = _toCanvas(0, 0);
        let g1 = _toCanvas(1, 1);
        let gW = g1.x - g0.x;
        let gH = g0.y - g1.y;

        ctx.strokeStyle = Qt.alpha(fg, 0.08);
        ctx.lineWidth = 0.5;
        for (let i = 0; i <= 10; i++) {
            let f = i / 10;
            ctx.beginPath(); ctx.moveTo(g0.x + f * gW, g1.y); ctx.lineTo(g0.x + f * gW, g0.y); ctx.stroke();
            ctx.beginPath(); ctx.moveTo(g0.x, g1.y + f * gH); ctx.lineTo(g1.x, g1.y + f * gH); ctx.stroke();
        }

        ctx.strokeStyle = Qt.alpha(fg, 0.25); ctx.lineWidth = 1;
        ctx.strokeRect(g0.x, g1.y, gW, gH);

        ctx.setLineDash([4, 4]);
        ctx.strokeStyle = Qt.alpha(fg, 0.15); ctx.lineWidth = 1;
        ctx.beginPath(); ctx.moveTo(g0.x, g0.y); ctx.lineTo(g1.x, g1.y); ctx.stroke();
        ctx.setLineDash([]);

        let cp1 = _toCanvas(x1, y1);
        let cp2 = _toCanvas(x2, y2);
        ctx.strokeStyle = Qt.alpha(fg, 0.35); ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.moveTo(g0.x, g0.y); ctx.lineTo(cp1.x, cp1.y); ctx.stroke();
        ctx.beginPath(); ctx.moveTo(g1.x, g1.y); ctx.lineTo(cp2.x, cp2.y); ctx.stroke();

        ctx.strokeStyle = Qt.alpha(accent, 1.0); ctx.lineWidth = 2.5;
        ctx.beginPath(); ctx.moveTo(g0.x, g0.y);
        let steps = 80;
        for (let i = 1; i <= steps; i++) {
            let t = i / steps;
            let pt = _toCanvas(_cubicBezier(t, x1, x2), _cubicBezier(t, y1, y2));
            ctx.lineTo(pt.x, pt.y);
        }
        ctx.stroke();

        let pts = [{ id: "p1", cx: cp1.x, cy: cp1.y }, { id: "p2", cx: cp2.x, cy: cp2.y }];
        for (let i = 0; i < pts.length; i++) {
            let p = pts[i];
            let active = _dragging === p.id;
            let col = active ? Qt.alpha(fg, 1.0) : Qt.alpha(accent, 1.0);

            ctx.fillStyle = col;
            ctx.beginPath(); ctx.arc(p.cx, p.cy, _handleRadius, 0, 2 * Math.PI); ctx.fill();

            ctx.fillStyle = "rgba(255,255,255,0.9)";
            ctx.beginPath(); ctx.arc(p.cx, p.cy, _handleRadius - 2, 0, 2 * Math.PI); ctx.fill();

            ctx.fillStyle = col;
            ctx.beginPath(); ctx.arc(p.cx, p.cy, _handleRadius - 4, 0, 2 * Math.PI); ctx.fill();
        }
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root._dragging !== "" ? Qt.ClosedHandCursor
            : root._hitTest(mouseX, mouseY) !== "" ? Qt.OpenHandCursor
            : Qt.ArrowCursor

        onPressed: (mouse) => {
            let hit = root._hitTest(mouse.x, mouse.y);
            if (hit === "") return;
            root._dragging = hit;
            let m = root._gridMetrics();
            root._dragScale = m.scale;
            root._dragStartX = mouse.x;
            root._dragStartY = mouse.y;
            root._dragOriginBx = hit === "p1" ? root.x1 : root.x2;
            root._dragOriginBy = hit === "p1" ? root.y1 : root.y2;
        }

        onPositionChanged: (mouse) => {
            if (root._dragging === "") return;
            let dx = mouse.x - root._dragStartX;
            let dy = mouse.y - root._dragStartY;
            let bx = root._dragOriginBx + dx / root._dragScale;
            let by = root._dragOriginBy - dy / root._dragScale;
            bx = Math.max(0.0, Math.min(1.0, Math.round(bx * 1000) / 1000));
            by = Math.round(by * 1000) / 1000;
            if (root._dragging === "p1") { root.x1 = bx; root.y1 = by; }
            else { root.x2 = bx; root.y2 = by; }
            root._updateViewRange();
            root.requestPaint();
            root.pointsChanged(root.x1, root.y1, root.x2, root.y2);
        }

        onReleased: {
            if (root._dragging !== "") {
                root._dragging = "";
                root._updateViewRange();
                root.requestPaint();
            }
        }
    }

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
}
