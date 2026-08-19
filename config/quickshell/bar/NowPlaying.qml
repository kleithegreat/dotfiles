import QtQuick
import Quickshell.Services.Mpris
import qs
import qs.ui as Ui

BarItem {
    id: root

    readonly property MprisPlayer player: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing)
                return players[i];
        }
        return players.length > 0 ? players[0] : null;
    }

    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing

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
