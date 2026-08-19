import QtQuick
import qs

// The standard row: leading glyph, a title over an optional subtitle, and a
// trailing slot. Every list in the shell is built from this, which is why they
// all align to the same grid without anyone measuring.
Pressable {
    id: root

    property string icon: ""
    property color iconColor: Theme.textSecondary
    // For rows whose leading mark is not a single glyph. Anything set here
    // replaces `icon`.
    property Component leading: null
    property string title: ""
    property string subtitle: ""
    property bool chevron: false
    property bool selected: false
    property int inset: Metrics.rowInset
    // Children of a ListRow land in the trailing slot, so a row that needs a
    // background of its own cannot simply declare one.
    property color tint: "transparent"

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root.tint
        antialiasing: true

        Behavior on color {
            Tint {}
        }
    }

    default property alias trailing: slot.data

    implicitWidth: parent ? parent.width : 240
    implicitHeight: subtitle !== "" ? Metrics.rowHeightTall : Metrics.rowHeight
    radius: Metrics.rControl
    active: selected
    pressScale: 1.0
    interactive: true

    Item {
        id: glyph
        width: root.leading || root.icon !== "" ? Metrics.icon : 0
        height: Metrics.icon
        anchors.left: parent.left
        anchors.leftMargin: root.inset
        anchors.verticalCenter: parent.verticalCenter

        Icon {
            anchors.fill: parent
            name: root.leading ? "" : root.icon
            size: Metrics.icon
            color: root.selected ? Theme.accent : root.iconColor
        }

        Loader {
            anchors.fill: parent
            sourceComponent: root.leading
        }
    }

    Column {
        id: text
        anchors.left: glyph.width === 0 ? parent.left : glyph.right
        anchors.leftMargin: glyph.width === 0 ? root.inset : Metrics.s3
        anchors.right: slot.left
        anchors.rightMargin: Metrics.s2
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Label {
            width: parent.width
            text: root.title
            role: "body"
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            text: root.subtitle
            role: "caption"
            elide: Text.ElideRight
            visible: root.subtitle !== ""
        }
    }

    Item {
        id: slot
        anchors.right: mark.visible ? mark.left : parent.right
        anchors.rightMargin: mark.visible ? Metrics.s1 : root.inset
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: childrenRect.width
        width: childrenRect.width
        height: parent.height
    }

    Icon {
        id: mark
        name: "chevron-right"
        size: Metrics.iconSm
        color: Theme.textQuaternary
        visible: root.chevron
        anchors.right: parent.right
        anchors.rightMargin: root.inset - 2
        anchors.verticalCenter: parent.verticalCenter
    }
}
