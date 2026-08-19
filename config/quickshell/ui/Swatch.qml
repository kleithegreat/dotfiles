import QtQuick
import Quickshell.Io
import qs

// A colour scheme shown as its own colours. A list of scheme names asks the
// reader to remember what "rose-pine-dawn" looks like.
Pressable {
    id: root

    property string scheme: ""
    property string directory: ""
    property bool selected: false

    property var colors: ({})

    implicitHeight: Metrics.rowHeightTall
    radius: Metrics.rCard
    showFill: false
    pressScale: 0.98

    FileView {
        path: root.directory === "" || root.scheme === "" ? "" : root.directory + "/" + root.scheme + ".json"
        onLoaded: {
            try {
                root.colors = JSON.parse(this.text()).colors || {};
            } catch (e) {
                root.colors = ({});
            }
        }
    }

    function tone(key, fallback) {
        return root.colors[key] ? root.colors[key] : fallback;
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        antialiasing: true
        color: root.selected ? Theme.accentSurface : Theme.raised
        border.width: Metrics.hairline
        border.color: root.selected ? Theme.accent : Theme.separator

        Behavior on border.color {
            Tint {
                duration: Motion.quick
            }
        }
        Behavior on color {
            Tint {
                duration: Motion.quick
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root.pressed ? Theme.fillPress : root.hovered ? Theme.fillHover : "transparent"
        antialiasing: true

        Behavior on color {
            Tint {}
        }
    }

    Row {
        id: chips
        anchors.left: parent.left
        anchors.leftMargin: Metrics.s3
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3

        Repeater {
            model: [root.tone("bg", "#282828"), root.tone("accent", "#458588"), root.tone("green", "#98971a"), root.tone("yellow", "#d79921"), root.tone("red", "#cc241d"), root.tone("fg", "#ebdbb2")]

            Rectangle {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 20
                radius: 3
                color: modelData
                antialiasing: true
                border.width: Metrics.hairline
                border.color: Theme.separator
            }
        }
    }

    Label {
        anchors.left: chips.right
        anchors.leftMargin: Metrics.s3
        anchors.right: parent.right
        anchors.rightMargin: Metrics.s3
        anchors.verticalCenter: parent.verticalCenter
        text: root.scheme
        role: "callout"
        font.weight: root.selected ? Theme.weightMedium : Theme.weightRegular
        elide: Text.ElideRight
    }
}
