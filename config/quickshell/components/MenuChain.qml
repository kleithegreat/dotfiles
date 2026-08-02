import QtQuick
import ".." as Root

// Cascading context menu host, the desktop-conventional counterpart to a
// StatusNotifierItem's DBus menu: a root panel anchored to whatever was
// right-clicked, with flyouts opening beside their parent row.
//
// Fill the area the menu may occupy (normally the popup overlay) and call
// openMenu(). Levels are held as plain records so a flyout swap rebinds the
// panel at that depth instead of tearing the whole chain down.
Item {
    id: chain

    // Each level: { handle, kind: "root"|"sub", rect }
    // rect is the anchor in chain coordinates -- the clicked item for the root,
    // and the parent panel's edge crossed with the hovered row for a flyout.
    property var levels: []
    property int maxDepth: 6

    readonly property bool open: levels.length > 0
    property bool closing: false

    // An entry was activated; callers usually dismiss their own popup too.
    signal activated()
    // The menu was dismissed without activating anything.
    signal dismissed()

    visible: open || closing

    function openMenu(handle, anchor) {
        if (!handle)
            return;

        closeAnim.stop();
        closing = false;
        opacity = 1;
        hoverTimer.stop();
        pending = null;
        levels = [{ handle: handle, kind: "root", rect: anchor }];
    }

    // Fade the whole chain out together; individual flyouts pop as they do on
    // every other desktop.
    function close() {
        if (!open || closing)
            return;

        hoverTimer.stop();
        pending = null;
        closing = true;
        closeAnim.restart();
    }

    function closeNow() {
        hoverTimer.stop();
        closeAnim.stop();
        pending = null;
        closing = false;
        levels = [];
        opacity = 1;
    }

    Anim {
        id: closeAnim
        target: chain
        property: "opacity"
        to: 0
        duration: Root.Theme.animPopupOut
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Root.Theme.animCurveExit
        onFinished: {
            chain.levels = [];
            chain.closing = false;
            chain.opacity = 1;
        }
    }

    // ── Flyout scheduling ──
    // Hovering dwells briefly before a flyout opens or closes so sweeping the
    // pointer across rows does not flash panels.
    property var pending: null

    Timer {
        id: hoverTimer
        interval: Root.Theme.menuHoverDelay
        onTriggered: chain.applyPending()
    }

    function submenuOpenAt(depth, handle) {
        return levels.length > depth + 1 && levels[depth + 1].handle === handle;
    }

    function requestSubmenu(depth, handle, anchor, immediate) {
        if (submenuOpenAt(depth, handle)) {
            hoverTimer.stop();
            pending = null;
            return;
        }

        pending = { depth: depth, handle: handle, rect: anchor };
        if (immediate)
            applyPending();
        else
            hoverTimer.restart();
    }

    function requestTruncate(depth) {
        if (levels.length <= depth + 1)
            return;

        pending = { depth: depth, handle: null, rect: null };
        hoverTimer.restart();
    }

    function applyPending() {
        hoverTimer.stop();
        if (!pending)
            return;

        let next = levels.slice(0, pending.depth + 1);
        if (pending.handle)
            next.push({ handle: pending.handle, kind: "sub", rect: pending.rect });

        levels = next;
        pending = null;
    }

    // ── Placement ──
    function placeX(level, w) {
        if (!level)
            return 0;

        let margin = Root.Theme.menuEdgeMargin;
        let maxX = Math.max(margin, chain.width - w - margin);
        let anchor = level.rect;

        if (level.kind === "root")
            return Math.min(maxX, Math.max(margin, anchor.x + anchor.width - w));

        let right = anchor.x + anchor.width - Root.Theme.menuSubmenuOverlap;
        if (right + w <= chain.width - margin)
            return right;

        return Math.max(margin, anchor.x - w + Root.Theme.menuSubmenuOverlap);
    }

    function placeY(level, h) {
        if (!level)
            return 0;

        let margin = Root.Theme.menuEdgeMargin;
        let maxY = Math.max(margin, chain.height - h - margin);
        let anchor = level.rect;

        if (level.kind === "root") {
            let below = anchor.y + anchor.height + Root.Theme.menuGap;
            if (below + h <= chain.height - margin)
                return below;

            return Math.max(margin, anchor.y - Root.Theme.menuGap - h);
        }

        return Math.min(maxY, Math.max(margin, anchor.y - Root.Theme.menuPadding));
    }

    // Clicking anywhere off the menu dismisses it without reaching the popup
    // underneath, matching how a real menu eats its dismiss click.
    MouseArea {
        anchors.fill: parent
        enabled: chain.open && !chain.closing
        acceptedButtons: Qt.AllButtons
        onPressed: {
            chain.close();
            chain.dismissed();
        }
    }

    Repeater {
        model: chain.maxDepth

        delegate: Loader {
            id: levelLoader
            required property int index

            readonly property var level: levelLoader.index < chain.levels.length
                ? chain.levels[levelLoader.index]
                : null

            active: level !== null
            visible: active
            x: chain.placeX(level, width)
            y: chain.placeY(level, height)
            z: levelLoader.index

            sourceComponent: MenuPanel {
                id: levelPanel

                menuHandle: levelLoader.level ? levelLoader.level.handle : null
                originCorner: {
                    if (!levelLoader.level)
                        return Item.TopLeft;
                    if (levelLoader.level.kind === "root")
                        return Item.TopRight;

                    // A flyout forced to the left of its parent grows from the right.
                    return levelLoader.x >= levelLoader.level.rect.x ? Item.TopLeft : Item.TopRight;
                }

                onSubmenuRequested: (entry, rowY, rowHeight, immediate) => {
                    let origin = levelPanel.mapToItem(chain, 0, rowY);
                    chain.requestSubmenu(levelLoader.index, entry,
                                         Qt.rect(origin.x, origin.y, levelPanel.width, rowHeight),
                                         immediate);
                }
                onPlainEntryHovered: chain.requestTruncate(levelLoader.index)
                onEntryTriggered: {
                    chain.closeNow();
                    chain.activated();
                }
            }
        }
    }
}
