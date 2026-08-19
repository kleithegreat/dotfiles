import QtQuick
import qs
import qs.ui as Ui

// A bar item whose whole content is one icon, optionally carrying an unread dot.
BarItem {
    id: root

    property string icon: ""
    property color tint: hovered ? Theme.text : Theme.textSecondary
    property bool badge: false

    contentWidth: Metrics.barIcon

    Ui.Icon {
        id: glyph
        anchors.centerIn: parent
        name: root.icon
        size: Metrics.barIcon
        color: root.tint
    }

    Rectangle {
        width: 6
        height: 6
        radius: 3
        color: Theme.accent
        visible: root.badge
        anchors.horizontalCenter: glyph.right
        anchors.verticalCenter: glyph.top
        antialiasing: true

        // The dot sits over the panel, so it needs its own edge to stay legible
        // against a busy glyph beneath it.
        border.width: 1.5
        border.color: Theme.glassBar
    }
}
