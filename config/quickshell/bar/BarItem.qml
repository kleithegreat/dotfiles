import QtQuick
import qs
import qs.ui as Ui
import qs.services as Sys

// Every clickable thing in the bar is this, which is the entire reason the bar
// reads as one object: identical height, identical corner, identical hover, and
// grouping expressed by spacing rather than by drawing lines between things.
Ui.Pressable {
    id: root

    property string hint: ""
    // The surface this item opens, published so a keybind can find it.
    property string surface: ""

    signal moved(string surface, real at)

    onXChanged: root.publish()
    onWidthChanged: root.publish()
    Component.onCompleted: root.publish()

    function publish() {
        if (surface !== "")
            root.moved(surface, root.anchorPoint());
    }

    // Screen x of this item's centre, handed to a surface so it can grow from
    // the control that summoned it instead of from its own middle. It has to be
    // asked for, never bound: mapping functions do not re-evaluate when geometry
    // changes, so a binding captures the position the item had while it was
    // still being built — which is zero, and every surface opens at the far
    // left of the screen.
    function anchorPoint() {
        return mapToItem(null, width / 2, 0).x + Metrics.barMargin;
    }

    signal activated(real anchor)

    onHoveredChanged: {
        if (hovered)
            Sys.Hint.request(root.hint, root.anchorPoint());
        else
            Sys.Hint.clear();
    }

    implicitHeight: Metrics.barItemHeight
    implicitWidth: Math.max(Metrics.barItemHeight, contentWidth + Metrics.s2 * 2)
    radius: Metrics.rControl
    pressScale: 0.94

    property real contentWidth: childrenRect.width

    onClicked: {
        Sys.Hint.clear();
        root.activated(root.anchorPoint());
    }
}
