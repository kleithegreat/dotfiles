import QtQuick
import qs

// Inactive arcs dimmed, not omitted: the bare glyphs sit below the optical centre.
Item {
    id: root

    property int strength: 0
    property color color: Theme.textSecondary
    property int size: Metrics.icon

    readonly property string variant: strength >= 75 ? "wifi" : strength >= 50 ? "wifi-good" : strength >= 25 ? "wifi-fair" : "wifi-poor"

    implicitWidth: size
    implicitHeight: size

    Icon {
        anchors.fill: parent
        name: "wifi"
        size: root.size
        color: Theme.withAlpha(root.color, 0.24)
    }

    Icon {
        anchors.fill: parent
        name: root.variant
        size: root.size
        color: root.color
    }
}
