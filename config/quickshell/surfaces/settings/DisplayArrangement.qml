import QtQuick
import qs
import qs.ui as Ui

// The outputs, to scale, where they sit. Dragging one reports where it landed;
// the pane stages that like any other display edit rather than applying it, so
// an arrangement you cannot see your way out of is still one countdown away
// from being undone.
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

    // Edges within this many *drawn* pixels of another edge are treated as
    // meant to touch. Working in drawn pixels rather than compositor ones keeps
    // the feel identical whatever the outputs' resolutions are.
    readonly property real snapDistance: 10

    // Every alignment a human means by dragging one panel near another: edges
    // flush, or the two abutting. Snapping per axis independently is what lets
    // a display sit above another and stay left-aligned with it.
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
        // Keyed on the count, not the array: rebinding a `var` array resets the
        // Repeater and destroys the delegate holding the pointer grab mid-drag.
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

                    Ui.Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.screen.name
                        role: "callout"
                    }

                    Ui.Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: tile.screen.width + " × " + tile.screen.height
                        role: "caption"
                        numeric: true
                    }
                }
            }

            // The tile is moved by an offset the binding adds, never by writing
            // `x` directly: `drag.target` would overwrite the binding and the
            // tile would stop following the staged position after the first drop.
            // Accumulating the delta is self-correcting — moving the item puts
            // the pointer back where it started relative to it.
            MouseArea {
                id: drag

                anchors.fill: parent
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                // A Flickable steals the grab from its children once a drag
                // passes the threshold; without this the tiles only twitch.
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
