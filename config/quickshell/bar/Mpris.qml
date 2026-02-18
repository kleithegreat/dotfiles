import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

Item {
    id: mprisRoot
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: player !== null
    signal labelClicked()

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null

    RowLayout {
        id: row; spacing: 6
        Text {
            text: "󰝚"; color: Theme.aquaBright
            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: mprisRoot.labelClicked() }
        }
        Text {
            text: {
                if (!mprisRoot.player) return "";
                let t = mprisRoot.player.trackTitle || "Unknown";
                let a = mprisRoot.player.trackArtist || "";
                return a ? a + " \u2014 " + t : t;
            }
            color: labelArea.containsMouse ? Theme.yellowBright : Theme.fg2
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight; Layout.maximumWidth: 220
            MouseArea { id: labelArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: mprisRoot.labelClicked() }
        }
        Text {
            text: "󰒮"
            color: prevA.containsMouse ? Theme.fg : ((mprisRoot.player?.canGoPrevious ?? false) ? Theme.fg3 : Theme.fg4)
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            MouseArea { id: prevA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: { if (mprisRoot.player?.canGoPrevious) mprisRoot.player.previous(); } }
        }
        Text {
            text: (mprisRoot.player?.isPlaying ?? false) ? "󰏤" : "󰐊"
            color: playA.containsMouse ? Theme.yellowBright : Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
            MouseArea { id: playA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: { if (mprisRoot.player?.canTogglePlaying ?? false) mprisRoot.player.isPlaying = !mprisRoot.player.isPlaying; } }
        }
        Text {
            text: "󰒭"
            color: nextA.containsMouse ? Theme.fg : ((mprisRoot.player?.canGoNext ?? false) ? Theme.fg3 : Theme.fg4)
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            MouseArea { id: nextA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: { if (mprisRoot.player?.canGoNext) mprisRoot.player.next(); } }
        }
    }
}
