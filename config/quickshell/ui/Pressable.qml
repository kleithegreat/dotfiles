import QtQuick
import qs

// The one interaction surface in the shell: hit target, hover fill, press
// response, cursor. Every clickable thing is this or contains this, so hover
// feels identical everywhere instead of being re-invented per widget.
Rectangle {
    id: root

    property bool interactive: true
    property bool active: false
    property bool showFill: true
    // Flickable steals the grab from children once a drag passes threshold. A
    // draggable control inside a scroll view must claim it; a button must not,
    // since dragging across a button is a legitimate scroll gesture.
    property bool claimsDrag: false
    property alias hovered: pointer.containsMouse
    property alias pressed: pointer.pressed
    property alias acceptedButtons: pointer.acceptedButtons
    property real pressScale: 0.97

    signal clicked
    signal rightClicked
    signal wheel(int delta)

    radius: Metrics.rControl
    color: !showFill ? "transparent" : root.active ? Theme.fillActive : pointer.pressed && interactive ? Theme.fillPress : pointer.containsMouse && interactive ? Theme.fillHover : "transparent"
    scale: pointer.pressed && interactive ? pressScale : 1.0
    transformOrigin: Item.Center
    antialiasing: true

    Behavior on color {
        Tint {}
    }

    Behavior on scale {
        Anim {
            duration: Motion.instant
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: true
        preventStealing: root.claimsDrag
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }

        onWheel: event => {
            root.wheel(event.angleDelta.y);
            event.accepted = false;
        }
    }
}
