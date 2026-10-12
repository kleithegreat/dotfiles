import QtQuick
import QtQuick.Effects
import qs

// Icons are addressed by name; this is the only place that knows where the files live.
Item {
    id: root

    property string name
    property color color: Theme.text
    property int size: Metrics.icon

    implicitWidth: size
    implicitHeight: size
    visible: name !== ""

    Image {
        id: glyph
        anchors.fill: parent
        source: root.name === "" ? "" : Qt.resolvedUrl("../icons/" + root.name + ".svg")
        // Rasterise at device pixels.
        sourceSize.width: Math.round(root.size * Screen.devicePixelRatio)
        sourceSize.height: Math.round(root.size * Screen.devicePixelRatio)
        fillMode: Image.PreserveAspectFit
        smooth: true
        visible: false
    }

    MultiEffect {
        anchors.fill: glyph
        source: glyph
        brightness: 1.0
        colorization: 1.0
        colorizationColor: root.color

        Behavior on colorizationColor {
            Tint {}
        }
    }
}
