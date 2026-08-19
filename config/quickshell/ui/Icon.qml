import QtQuick
import QtQuick.Effects
import qs

// Icons are addressed by name, never by path. The old shell passed relative
// paths between directories and then repaired them with string surgery at the
// point of use; the name is the stable identifier and this is the only place
// that knows where the files live.
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
        // Rasterise at device pixels; an SVG scaled up from a smaller raster is
        // the whole reason the old icons looked soft.
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
