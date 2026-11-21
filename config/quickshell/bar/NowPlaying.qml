import QtQuick
import Quickshell.Services.Mpris
import qs
import qs.ui as Ui
import qs.services as Sys

BarItem {
    id: root

    readonly property MprisPlayer player: Sys.Media.player
    readonly property bool playing: Sys.Media.playing

    visible: player !== null
    contentWidth: line.implicitWidth

    Row {
        id: line
        anchors.centerIn: parent
        spacing: Metrics.s2

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            size: Metrics.barIcon
            name: root.playing ? "player-play" : "player-pause"
            color: root.hovered ? Theme.text : Theme.textTertiary
        }

        Ui.Label {
            anchors.verticalCenter: parent.verticalCenter
            text: root.player?.trackTitle ?? ""
            role: "callout"
            color: root.hovered ? Theme.text : Theme.textSecondary
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 180)
        }
    }
}
