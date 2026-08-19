import QtQuick
import qs

// A Control Centre tile. Pressing the body toggles; the corner affordance opens
// the full surface for that capability. One "on" treatment, used everywhere.
Pressable {
    id: root

    property string icon: ""
    property string title: ""
    property string detail: ""
    property bool on: false
    property bool pending: false
    property bool expandable: false

    signal expand

    implicitHeight: Metrics.rowHeightTall + Metrics.s2
    radius: Metrics.rCard
    showFill: false
    pressScale: 0.98
    opacity: pending ? 0.7 : 1.0

    Behavior on opacity {
        Anim {}
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        antialiasing: true
        color: root.on ? Theme.accentSurface : Theme.raised
        border.width: Metrics.hairline
        border.color: root.on ? Theme.accentSoft : Theme.separator

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: root.pressed ? Theme.fillPress : root.hovered ? Theme.fillHover : "transparent"
            antialiasing: true

            Behavior on color {
                Tint {}
            }
        }

        Behavior on color {
            Tint {
                duration: Motion.quick
            }
        }
        Behavior on border.color {
            Tint {
                duration: Motion.quick
            }
        }
    }

    Icon {
        id: glyph
        name: root.icon
        size: Metrics.iconLg
        color: root.on ? Theme.accent : Theme.textSecondary
        anchors.left: parent.left
        anchors.leftMargin: Metrics.s3
        anchors.verticalCenter: parent.verticalCenter
    }

    Column {
        anchors.left: glyph.right
        anchors.leftMargin: Metrics.s3
        anchors.right: parent.right
        anchors.rightMargin: root.expandable ? Metrics.s5 + Metrics.s1 : Metrics.s3
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Label {
            width: parent.width
            text: root.title
            role: "callout"
            font.weight: Theme.weightMedium
            elide: Text.ElideRight
        }

        Label {
            width: parent.width
            text: root.detail
            role: "caption"
            elide: Text.ElideRight
            visible: text !== ""
        }
    }

    Pressable {
        width: Metrics.s5
        height: Metrics.s5
        radius: Metrics.rControl
        visible: root.expandable
        anchors.right: parent.right
        anchors.rightMargin: Metrics.s1 + 2
        anchors.verticalCenter: parent.verticalCenter
        onClicked: root.expand()

        Icon {
            anchors.centerIn: parent
            name: "chevron-right"
            size: Metrics.iconSm
            color: Theme.textTertiary
        }
    }
}
