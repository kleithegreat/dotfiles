import QtQuick
import QtQuick.Effects
import ".." as Root

Item {
    id: root

    property url source
    property color color: Root.Theme.fg
    property real iconSize: Root.Theme.iconSize
    property alias status: img.status

    implicitWidth: iconSize
    implicitHeight: iconSize

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(root.width * 2, root.height * 2)
        visible: false
        fillMode: Image.PreserveAspectFit
    }

    MultiEffect {
        anchors.fill: img
        source: img
        brightness: 1.0
        colorization: 1.0
        colorizationColor: root.color
    }
}
