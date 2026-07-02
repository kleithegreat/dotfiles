import QtQuick
import ".." as Root

MouseArea {
    id: root

    // Fill-parent interactive wrapper. Place visual children inside this item
    // so the hover layer stays behind them.
    property bool disabled: false
    // Invisible hit-area mode: no hover/press visuals and no press scale.
    property bool flat: false
    property color color: Root.Theme.bg2
    property real radius: {
        if (!root.parent)
            return Root.Theme.hoverRadius;

        let parentRadius = root.parent.radius;
        return parentRadius === undefined ? Root.Theme.hoverRadius : parentRadius;
    }
    property real idleOpacity: 0.0
    property real hoverOpacity: flat ? 0.0 : 0.6
    property real pressedOpacity: flat ? 0.0 : 0.9
    property real pressedScale: flat ? 1.0 : 0.98

    anchors.fill: parent
    enabled: !root.disabled
    hoverEnabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    scale: root.enabled && root.pressed ? root.pressedScale : 1.0
    transformOrigin: Item.Center

    Rectangle {
        id: hoverBg
        anchors.fill: parent
        radius: root.radius
        color: root.color
        opacity: {
            if (!root.enabled)
                return root.idleOpacity;

            if (root.pressed)
                return root.pressedOpacity;

            return root.containsMouse ? root.hoverOpacity : root.idleOpacity;
        }

        Behavior on color {
            CAnim {
                duration: Root.Theme.animHover
            }
        }

        Behavior on opacity {
            Anim {
                duration: Root.Theme.animHover
            }
        }
    }

    Behavior on scale {
        Anim {
            duration: Root.Theme.animMicro
        }
    }
}
