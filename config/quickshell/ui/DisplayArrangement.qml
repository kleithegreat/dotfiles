import QtQuick
import qs

// Drags are staged like any display edit, so a bad arrangement is one countdown from undone.
Item {
    id: root

    // [{ name, x, y, width, height, primary }] in compositor coordinates.
    property var layout: []

    signal moved(string name, int x, int y)

    implicitHeight: 172

    readonly property real pad: Metrics.s4

    readonly property var bounds: {
        if (layout.length === 0)
            return { x: 0, y: 0, width: 1, height: 1 };
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (let i = 0; i < layout.length; i++) {
            const screen = layout[i];
            minX = Math.min(minX, screen.x);
            minY = Math.min(minY, screen.y);
            maxX = Math.max(maxX, screen.x + screen.width);
            maxY = Math.max(maxY, screen.y + screen.height);
        }
        return { x: minX, y: minY, width: Math.max(1, maxX - minX), height: Math.max(1, maxY - minY) };
    }

    readonly property real factor: Math.min((width - pad * 2) / bounds.width, (height - pad * 2) / bounds.height)
    readonly property real originX: (width - bounds.width * factor) / 2 - bounds.x * factor
    readonly property real originY: (height - bounds.height * factor) / 2 - bounds.y * factor

    // In drawn pixels, so snapping feels the same at any output resolution.
    readonly property real snapDistance: 10

    // Per axis, so a display can sit above another and stay left-aligned with it.
    function snap(name, candidate, size, axis) {
        const tolerance = snapDistance / factor;
        let best = candidate;
        let bestGap = tolerance;

        for (let i = 0; i < layout.length; i++) {
            const other = layout[i];
            if (other.name === name)
                continue;
            const start = axis === "x" ? other.x : other.y;
            const extent = axis === "x" ? other.width : other.height;
            const targets = [start, start + extent - size, start - size, start + extent];
            for (let t = 0; t < targets.length; t++) {
                const gap = Math.abs(candidate - targets[t]);
                if (gap < bestGap) {
                    bestGap = gap;
                    best = targets[t];
                }
            }
        }
        return Math.round(best);
    }

    Repeater {
        // Keyed on the count: an array model kills the drag ([[quickshell]]).
        model: root.layout.length

        Item {
            id: tile

            required property int index
            readonly property var screen: root.layout[tile.index]

            property real slipX: 0
            property real slipY: 0

            x: root.originX + screen.x * root.factor + slipX
            y: root.originY + screen.y * root.factor + slipY
            width: screen.width * root.factor
            height: screen.height * root.factor

            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Metrics.rControl
                color: tile.screen.primary ? Theme.accentSurface : Theme.raised
                border.width: drag.pressed ? 2 : 1
                border.color: tile.screen.primary ? Theme.accent : Theme.separator

                Column {
                    anchors.centerIn: parent
                    spacing: 1

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.screen.name
                        role: "callout"
                    }

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.screen.width + " × " + tile.screen.height
                        role: "caption"
                        numeric: true
                    }
                }
            }

            // Moved by an offset the binding adds: `drag.target` would break the binding.
            MouseArea {
                id: drag

                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                // See "claimsDrag" in docs/quickshell.md.
                preventStealing: true

                property real grabX: 0
                property real grabY: 0

                onPressed: mouse => {
                    grabX = mouse.x;
                    grabY = mouse.y;
                }

                onPositionChanged: mouse => {
                    if (!pressed)
                        return;
                    tile.slipX += mouse.x - grabX;
                    tile.slipY += mouse.y - grabY;
                }

                onReleased: {
                    const x = tile.screen.x + tile.slipX / root.factor;
                    const y = tile.screen.y + tile.slipY / root.factor;
                    tile.slipX = 0;
                    tile.slipY = 0;
                    root.moved(tile.screen.name, root.snap(tile.screen.name, x, tile.screen.width, "x"), root.snap(tile.screen.name, y, tile.screen.height, "y"));
                }
            }
        }
    }
}
