import QtQuick
import QtQuick.Effects
import qs

Item {
    id: root

    property real radius: Metrics.rPanel
    property color tint: Theme.base
    property real elevation: 22
    // Room a host window must leave around this surface for its shadow.
    readonly property int shadowPad: Metrics.shadowReach(elevation)
    // Keeps NativeRendering text sharp through a scale; layering the surface clips its shadow ([[quickshell]]).
    property bool flatten: false

    default property alias content: holder.data

    RectangularShadow {
        anchors.fill: body
        radius: body.radius
        blur: root.elevation
        spread: 0
        offset: Qt.vector2d(0, Metrics.shadowDrop(root.elevation))
        color: Theme.shadow
        cached: true
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: root.radius
        color: root.tint
        border.width: Metrics.hairline
        border.color: Theme.rim
        antialiasing: true

        Behavior on color {
            Tint {
                duration: Motion.quick
            }
        }
    }

    Item {
        id: holder
        anchors.fill: parent
        layer.enabled: root.flatten
    }
}
