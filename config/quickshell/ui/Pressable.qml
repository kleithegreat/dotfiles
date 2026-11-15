import QtQuick
import qs

// Every clickable thing is or contains this, so hover is identical everywhere.
Rectangle {
    id: root

    property bool interactive: true
    property bool active: false
    property bool showFill: true
    // Draggable controls in a Scroll claim the grab; buttons must not ([[quickshell]]).
    property bool claimsDrag: false
    property alias hovered: pointer.containsMouse
    property alias pressed: pointer.pressed
    property alias acceptedButtons: pointer.acceptedButtons
    property real pressScale: 0.97

    signal clicked
    signal rightClicked

    radius: Metrics.rControl
    color: !showFill ? "transparent" : root.active ? Theme.fillActive : pointer.pressed && interactive ? Theme.fillPress : pointer.containsMouse && interactive ? Theme.fillHover : "transparent"
    scale: pointer.pressed && interactive ? pressScale : 1.0
    transformOrigin: Item.Center
    antialiasing: true

    Behavior on color {
        Tint {}
    }

    // A press goes in at once; letting go springs back past rest.
    Reveal on scale {
        shownValue: root.pressScale
        enterDuration: Motion.instant
        enterCurve: Motion.standard
        exitDuration: Motion.settled
        exitCurve: Motion.spring
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
    }
}
