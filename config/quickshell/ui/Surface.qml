import QtQuick
import QtQuick.Effects
import qs

// A floating material: a tinted body over the compositor's blur, a hairline
// that lifts its top edge, and a wide soft shadow. Without them a translucent
// rectangle reads as a hole rather than an object — but overstate any of them
// and it reads as a bevel.
Item {
    id: root

    property real radius: Metrics.rPanel
    property bool glass: true
    property color tint: glass ? Theme.glassPanel : Theme.solid
    property bool shadow: true
    property real elevation: 22
    property bool specular: glass
    // Flattening the content protects NativeRendering text through a scale.
    // Layering the surface instead clips its shadow ([[quickshell]]).
    property bool flatten: false

    default property alias content: holder.data

    RectangularShadow {
        anchors.fill: body
        radius: body.radius
        blur: root.elevation
        spread: 0
        offset: Qt.vector2d(0, Math.round(root.elevation / 4))
        color: Theme.shadow
        visible: root.shadow
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

    Rectangle {
        anchors.fill: body
        anchors.margins: Metrics.hairline
        radius: Metrics.inner(body.radius, Metrics.hairline)
        visible: root.specular
        antialiasing: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: Theme.specularFade }
            GradientStop { position: 0.22; color: "transparent" }
        }
    }

    Item {
        id: holder
        anchors.fill: parent
        layer.enabled: root.flatten
    }
}
