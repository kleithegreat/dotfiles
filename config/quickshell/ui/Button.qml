import QtQuick
import qs

Pressable {
    id: root

    // plain · tinted · filled · destructive
    property string variant: "plain"
    property string text: ""
    property string icon: ""

    readonly property bool _filled: variant === "filled" || variant === "destructive"
    readonly property color _ground: variant === "filled" ? Theme.accent : variant === "destructive" ? Theme.critical : variant === "tinted" ? Theme.accentSoft : "transparent"
    readonly property color _ink: variant === "filled" ? Theme.onAccent : variant === "destructive" ? Theme.onAccent : variant === "tinted" ? Theme.accent : Theme.text

    implicitWidth: strip.implicitWidth + Metrics.s4 * 2
    implicitHeight: Metrics.controlHeight
    radius: Metrics.rControl
    showFill: variant === "plain"
    opacity: interactive ? 1.0 : 0.4

    Behavior on opacity {
        Anim {}
    }

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: root._ground
        opacity: root.pressed ? 0.82 : root.hovered ? (root._filled ? 0.9 : 1.0) : 1.0
        visible: root.variant !== "plain"
        antialiasing: true

        Behavior on color {
            Tint {}
        }
        Behavior on opacity {
            Anim {
                duration: Motion.instant
            }
        }
    }

    Row {
        id: strip
        anchors.centerIn: parent
        spacing: Metrics.s1 + 2

        Icon {
            name: root.icon
            size: Metrics.iconSm
            color: root._ink
            anchors.verticalCenter: parent.verticalCenter
        }

        Label {
            text: root.text
            role: "callout"
            color: root._ink
            font.weight: Theme.weightMedium
            visible: text !== ""
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
