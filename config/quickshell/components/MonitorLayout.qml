import QtQuick
import ".." as Root

Item {
    id: root

    property var monitors: []
    property int selectedIndex: -1
    property bool draggable: true

    // True when the cursor is over a draggable monitor rect, or a drag is active.
    // The parent flickable should bind `interactive: !monitorLayout.hoveringMonitor`
    // so its built-in drag handling doesn't steal the gesture.
    readonly property bool hoveringMonitor: draggable
        && (dragArea.containsMouse && _hitTest(dragArea.mouseX, dragArea.mouseY) >= 0
            || _draggingIdx >= 0)

    signal dragStarted()
    signal dragEnded()
    signal monitorClicked(int index)

    implicitHeight: 180

    // Layout transform
    // Maps monitor pixel coords → canvas coords
    property real _pad: 16
    property real _layoutScale: 1.0
    property real _layoutOx: 0
    property real _layoutOy: 0
    property real _minX: 0
    property real _minY: 0

    // Drag state
    property int _draggingIdx: -1
    property bool _dragMoved: false
    property real _dragStartCanvasX: 0
    property real _dragStartCanvasY: 0
    property int _dragStartMonX: 0
    property int _dragStartMonY: 0

    onMonitorsChanged: _recalcLayout()
    onWidthChanged: _recalcLayout()
    onHeightChanged: _recalcLayout()

    function effectiveSize(mon) {
        let t = mon.transform || 0;
        // Transforms 1,3,5,7 swap width/height
        if (t === 1 || t === 3 || t === 5 || t === 7)
            return { w: mon.height / mon.scale, h: mon.width / mon.scale };
        return { w: mon.width / mon.scale, h: mon.height / mon.scale };
    }

    function _recalcLayout() {
        if (!monitors || monitors.length === 0 || root.width <= 0 || root.height <= 0)
            return;

        let independent = [];
        for (let i = 0; i < monitors.length; i++) {
            if (!monitors[i].disabled && monitors[i].mirrorOf === "none")
                independent.push(monitors[i]);
        }
        if (independent.length === 0) return;

        let minX = independent[0].x, minY = independent[0].y;
        let maxX = minX, maxY = minY;
        for (let i = 0; i < independent.length; i++) {
            let m = independent[i];
            let es = effectiveSize(m);
            if (m.x < minX) minX = m.x;
            if (m.y < minY) minY = m.y;
            if (m.x + es.w > maxX) maxX = m.x + es.w;
            if (m.y + es.h > maxY) maxY = m.y + es.h;
        }

        let totalW = maxX - minX;
        let totalH = maxY - minY;
        if (totalW <= 0 || totalH <= 0) return;

        let pad = _pad;
        let sx = (root.width - 2 * pad) / totalW;
        let sy = (root.height - 2 * pad) / totalH;
        let s = Math.min(sx, sy);

        let drawnW = totalW * s;
        let drawnH = totalH * s;

        _layoutScale = s;
        _layoutOx = (root.width - drawnW) / 2;
        _layoutOy = (root.height - drawnH) / 2;
        _minX = minX;
        _minY = minY;
    }

    function _monToCanvasX(mx) { return _layoutOx + (mx - _minX) * _layoutScale; }
    function _monToCanvasY(my) { return _layoutOy + (my - _minY) * _layoutScale; }

    function _hitTest(cx, cy) {
        let s = _layoutScale;
        if (s <= 0) return -1;
        // Reverse iteration for z-order
        for (let i = monitors.length - 1; i >= 0; i--) {
            let m = monitors[i];
            if (m.disabled || m.mirrorOf !== "none") continue;
            let es = effectiveSize(m);
            let mx = _monToCanvasX(m.x);
            let my = _monToCanvasY(m.y);
            let mw = es.w * s;
            let mh = es.h * s;
            if (cx >= mx && cx <= mx + mw && cy >= my && cy <= my + mh)
                return i;
        }
        return -1;
    }

    // Collision resolution (ported from hyprmod)
    function _resolveCollisions(dragIdx, x, y) {
        if (monitors.length < 2) return { x: x, y: y };
        let dragged = monitors[dragIdx];
        let ds = effectiveSize(dragged);
        let dw = ds.w, dh = ds.h;
        let sx = _dragStartMonX, sy = _dragStartMonY;

        for (let i = 0; i < monitors.length; i++) {
            if (i === dragIdx || monitors[i].disabled || monitors[i].mirrorOf !== "none") continue;
            let other = monitors[i];
            let os = effectiveSize(other);
            let ow = os.w, oh = os.h;
            let ox = other.x, oy = other.y;

            // AABB overlap check
            if (!(x < ox + ow && x + dw > ox && y < oy + oh && y + dh > oy))
                continue;

            // Which axes were separated at drag start?
            let hSep = (sx + dw <= ox) || (sx >= ox + ow);
            let vSep = (sy + dh <= oy) || (sy >= oy + oh);

            let candidates = [];
            if (hSep) {
                if (x + dw / 2 < ox + ow / 2)
                    candidates.push({ nx: ox - dw, ny: y, dist: (x + dw) - ox });
                else
                    candidates.push({ nx: ox + ow, ny: y, dist: (ox + ow) - x });
            }
            if (vSep) {
                if (y + dh / 2 < oy + oh / 2)
                    candidates.push({ nx: x, ny: oy - dh, dist: (y + dh) - oy });
                else
                    candidates.push({ nx: x, ny: oy + oh, dist: (oy + oh) - y });
            }

            if (candidates.length === 0) {
                // Started overlapping — push on dominant axis
                if (Math.abs(x + dw / 2 - ox - ow / 2) * (dh + oh)
                        >= Math.abs(y + dh / 2 - oy - oh / 2) * (dw + ow)) {
                    x = (x + dw / 2 < ox + ow / 2) ? ox - dw : ox + ow;
                } else {
                    y = (y + dh / 2 < oy + oh / 2) ? oy - dh : oy + oh;
                }
                continue;
            }

            let best = candidates[0];
            for (let c = 1; c < candidates.length; c++) {
                if (candidates[c].dist < best.dist)
                    best = candidates[c];
            }
            x = best.nx;
            y = best.ny;
        }
        return { x: x, y: y };
    }

    // Bounding-box clamping (ported from hyprmod)
    function _clampToNeighbors(dragIdx, x, y) {
        let dragged = monitors[dragIdx];
        let ds = effectiveSize(dragged);
        let dw = ds.w, dh = ds.h;
        let maxFactor = 3;

        let active = [];
        for (let i = 0; i < monitors.length; i++) {
            if (!monitors[i].disabled && monitors[i].mirrorOf === "none")
                active.push({ idx: i, mon: monitors[i] });
        }
        if (active.length < 2) return { x: x, y: y };

        let contentW = 0, contentH = 0;
        for (let i = 0; i < active.length; i++) {
            let es = effectiveSize(active[i].mon);
            contentW += es.w;
            contentH += es.h;
        }
        let maxW = contentW * maxFactor;
        let maxH = contentH * maxFactor;

        let others = active.filter(function(a) { return a.idx !== dragIdx; });
        let minOx = others[0].mon.x, minOy = others[0].mon.y;
        let maxOx = minOx, maxOy = minOy;
        for (let i = 0; i < others.length; i++) {
            let m = others[i].mon;
            let es = effectiveSize(m);
            if (m.x < minOx) minOx = m.x;
            if (m.y < minOy) minOy = m.y;
            if (m.x + es.w > maxOx) maxOx = m.x + es.w;
            if (m.y + es.h > maxOy) maxOy = m.y + es.h;
        }

        x = Math.max(x, Math.min(minOx, maxOx - maxW));
        x = Math.min(x, Math.max(maxOx, minOx + maxW) - dw);
        y = Math.max(y, Math.min(minOy, maxOy - maxH));
        y = Math.min(y, Math.max(maxOy, minOy + maxH) - dh);

        return { x: x, y: y };
    }

    // Mirror lookup
    function _mirrorBadges(monitorName) {
        let badges = [];
        for (let i = 0; i < monitors.length; i++) {
            if (monitors[i].mirrorOf === monitorName)
                badges.push(i + 1);
        }
        return badges;
    }

    // Monitor rectangles
    Repeater {
        id: monRepeater
        model: root.monitors

        delegate: Item {
            id: monItem
            required property var modelData
            required property int index

            visible: !modelData.disabled && modelData.mirrorOf === "none"

            property var es: root.effectiveSize(modelData)
            x: root._monToCanvasX(modelData.x)
            y: root._monToCanvasY(modelData.y)
            width: es.w * root._layoutScale
            height: es.h * root._layoutScale

            property bool isSelected: index === root.selectedIndex
            property bool isFocused: modelData.focused
            property bool isDragging: index === root._draggingIdx

            // Background fill
            Rectangle {
                anchors.fill: parent
                color: monItem.isSelected ? Qt.alpha(Root.Theme.accent, 0.15)
                     : Qt.alpha(Root.Theme.fg, 0.06)
                Behavior on color { CAnim { duration: Root.Theme.animHover } }
            }

            // Border
            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: monItem.isDragging ? 2 : 1.5
                border.color: monItem.isSelected ? Qt.alpha(Root.Theme.accent, 0.7)
                            : Qt.alpha(Root.Theme.fg, 0.3)
                Behavior on border.color { CAnim { duration: Root.Theme.animHover } }
            }

            // Large index number
            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -6
                text: String(monItem.index + 1)
                color: monItem.isSelected ? Qt.alpha(Root.Theme.accent, 0.6)
                     : Qt.alpha(Root.Theme.fg, 0.2)
                font.family: Root.Theme.fontFamily
                font.pixelSize: Math.min(monItem.width, monItem.height) * 0.35
                font.bold: true
            }

            // Monitor name label at bottom
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: monItem.modelData.name
                color: Qt.alpha(Root.Theme.fg, 0.6)
                font.family: Root.Theme.fontFamily
                font.pixelSize: Root.Theme.fontSizeSmall
            }

            // Mirror badges (top-right)
            Row {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 4
                spacing: 3
                layoutDirection: Qt.RightToLeft

                Repeater {
                    model: root._mirrorBadges(monItem.modelData.name)
                    delegate: Rectangle {
                        required property var modelData
                        width: badgeText.implicitWidth + 8
                        height: badgeText.implicitHeight + 4
                        color: Qt.alpha(Root.Theme.accent, 0.25)
                        border.width: 1
                        border.color: Qt.alpha(Root.Theme.accent, 0.6)
                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: String(modelData)
                            color: Qt.alpha(Root.Theme.accent, 0.8)
                            font.family: Root.Theme.fontFamily
                            font.pixelSize: Math.min(monItem.width, monItem.height) * 0.18
                        }
                    }
                }
            }
        }
    }

    // Drag overlay
    MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: root.draggable
        hoverEnabled: true
        cursorShape: {
            if (root._draggingIdx >= 0) return Qt.ClosedHandCursor;
            if (root._hitTest(mouseX, mouseY) >= 0) return Qt.OpenHandCursor;
            return Qt.ArrowCursor;
        }

        onPressed: (mouse) => {
            let idx = root._hitTest(mouse.x, mouse.y);
            if (idx >= 0) {
                root._draggingIdx = idx;
                root._dragMoved = false;
                root._dragStartCanvasX = mouse.x;
                root._dragStartCanvasY = mouse.y;
                root._dragStartMonX = root.monitors[idx].x;
                root._dragStartMonY = root.monitors[idx].y;
            }
        }

        onPositionChanged: (mouse) => {
            if (root._draggingIdx < 0) return;
            let s = root._layoutScale;
            if (s <= 0) return;

            let dx = (mouse.x - root._dragStartCanvasX) / s;
            let dy = (mouse.y - root._dragStartCanvasY) / s;
            let newX = Math.round((root._dragStartMonX + dx) / 10) * 10;
            let newY = Math.round((root._dragStartMonY + dy) / 10) * 10;

            let resolved = root._resolveCollisions(root._draggingIdx, newX, newY);
            let clamped = root._clampToNeighbors(root._draggingIdx, resolved.x, resolved.y);
            newX = clamped.x;
            newY = clamped.y;

            let mon = root.monitors[root._draggingIdx];
            if (mon.x !== newX || mon.y !== newY) {
                if (!root._dragMoved)
                    root.dragStarted();
                mon.x = newX;
                mon.y = newY;
                root._dragMoved = true;
                root.monitorsChanged();
                root._recalcLayout();
            }
        }

        onReleased: {
            let moved = root._draggingIdx >= 0 && root._dragMoved;
            let idx = root._draggingIdx;
            root._draggingIdx = -1;
            if (moved) {
                root.dragEnded();
            } else if (idx >= 0) {
                root.monitorClicked(idx);
            }
        }
    }
}
