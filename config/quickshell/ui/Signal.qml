import QtQuick
import qs

// Signal strength drawn as the full arc set with the inactive arcs dimmed.
// The bare progressive glyphs only draw the arcs they mean, and because those
// paths sit in the lower half of the 24px grid, a weak signal renders as a
// small mark floating below the optical centre of every icon beside it.
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
