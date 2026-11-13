import QtQuick
import QtQuick.Effects
import qs

// A picture with rounded corners, or an icon on a tile when there is none or
// the file is not one Qt can draw.
Item {
    id: root

    property url source: ""
    property string fallback: "photo"
    property real radius: Metrics.rCard
    readonly property bool loaded: picture.status === Image.Ready

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Theme.fillTrack
        visible: !root.loaded

        Icon {
            anchors.centerIn: parent
            name: root.fallback
            size: Math.round(Math.min(parent.width, parent.height) * 0.45)
            color: Theme.textSecondary
        }
    }

    Image {
        id: picture
        anchors.fill: parent
        source: root.source
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.round(width * Screen.devicePixelRatio)
        sourceSize.height: Math.round(height * Screen.devicePixelRatio)
        visible: false
    }

    Item {
        id: corners
        width: root.width
        height: root.height
        visible: false
        layer.enabled: true

        Rectangle {
            width: root.width
            height: root.height
            radius: root.radius
            antialiasing: true
        }
    }

    MultiEffect {
        anchors.fill: picture
        source: picture
        maskEnabled: true
        maskSource: corners
        visible: root.loaded
    }
}
