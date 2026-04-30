import QtQuick
import QtQuick.Effects
import ".." as Root

Item {
    id: root

    property string source
    property color color: Root.Theme.fg
    property real iconSize: Root.Theme.iconSize
    property alias status: img.status

    function resolvedSource(path) {
        if (path === "")
            return "";

        let text = String(path);
        let marker = "icons/";
        let markerIndex = text.lastIndexOf(marker);
        if (markerIndex >= 0)
            return "../icons/" + text.slice(markerIndex + marker.length);
        if (text.startsWith("icons/"))
            return "../" + text;

        return text;
    }

    implicitWidth: iconSize
    implicitHeight: iconSize

    Image {
        id: img
        anchors.fill: parent
        source: root.resolvedSource(root.source)
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
