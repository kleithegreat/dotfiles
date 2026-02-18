import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

Item {
    id: mprisRoot
    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    visible: player !== null

    property var player: Mpris.players.values.length > 0
        ? Mpris.players.values[0] : null

    RowLayout {
        id: row
        spacing: 6

        Text {
            text: "󰝚"
            color: Theme.aquaBright
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
        }

        Text {
            text: {
                if (!mprisRoot.player) return "";
                let t = mprisRoot.player.trackTitle || "Unknown";
                let a = mprisRoot.player.trackArtist || "";
                let label = a ? a + " — " + t : t;
                return label.length > 30
                    ? label.substring(0, 28) + "…" : label;
            }
            color: Theme.fg2
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        // Prev
        Text {
            text: "󰒮"
            color: (mprisRoot.player?.canGoPrevious ?? false)
                ? Theme.fg : Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (mprisRoot.player?.canGoPrevious)
                        mprisRoot.player.previous();
                }
            }
        }

        // Play/Pause
        Text {
            text: (mprisRoot.player?.isPlaying ?? false)
                ? "󰏤" : "󰐊"
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (mprisRoot.player?.canTogglePlaying ?? false)
                        mprisRoot.player.isPlaying = !mprisRoot.player.isPlaying;
                }
            }
        }

        // Next
        Text {
            text: "󰒭"
            color: (mprisRoot.player?.canGoNext ?? false)
                ? Theme.fg : Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (mprisRoot.player?.canGoNext)
                        mprisRoot.player.next();
                }
            }
        }
    }
}
