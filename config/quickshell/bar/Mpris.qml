import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../components" as Components

Item {
    id: mprisRoot
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: player !== null && (player.trackTitle ?? "") !== ""
    signal labelClicked()

    property var player: {
        let players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying) return players[i];
        }
        for (let i = 0; i < players.length; i++) {
            if (players[i].trackTitle) return players[i];
        }
        return null;
    }

    RowLayout {
        id: row; spacing: 6
        Components.Icon {
            source: "../icons/music.svg"; color: Theme.aquaBright
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mprisRoot.labelClicked() }
        }
        Text {
            text: {
                if (!mprisRoot.player) return "";
                let t = mprisRoot.player.trackTitle || "";
                let a = mprisRoot.player.trackArtist || "";
                return a ? a + " \u2014 " + t : t;
            }
            color: labelArea.containsMouse ? Theme.yellowBright : Theme.fg2
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight; Layout.maximumWidth: 220
            MouseArea { id: labelArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: mprisRoot.labelClicked() }
        }
        Components.Icon {
            source: "../icons/player-prev.svg"
            color: prevA.containsMouse ? Theme.fg : ((mprisRoot.player?.canGoPrevious ?? false) ? Theme.fg3 : Theme.fg4)
            iconSize: Theme.fontSizeSmall
            MouseArea { id: prevA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: { if (mprisRoot.player?.canGoPrevious) mprisRoot.player.previous(); } }
        }
        Components.Icon {
            source: (mprisRoot.player?.isPlaying ?? false) ? "../icons/player-pause.svg" : "../icons/player-play.svg"
            color: playA.containsMouse ? Theme.yellowBright : Theme.fg
            MouseArea { id: playA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: { if (mprisRoot.player?.canTogglePlaying ?? false) mprisRoot.player.isPlaying = !mprisRoot.player.isPlaying; } }
        }
        Components.Icon {
            source: "../icons/player-next.svg"
            color: nextA.containsMouse ? Theme.fg : ((mprisRoot.player?.canGoNext ?? false) ? Theme.fg3 : Theme.fg4)
            iconSize: Theme.fontSizeSmall
            MouseArea { id: nextA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: { if (mprisRoot.player?.canGoNext) mprisRoot.player.next(); } }
        }
    }
}
