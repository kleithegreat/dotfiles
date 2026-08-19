import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import qs
import qs.ui as Ui

Popover {
    id: root

    required property ShellState state

    shown: state.isOpen("media")
    anchor: state.anchor
    panelWidth: Metrics.panelWide
    contentHeight: player_.implicitHeight

    readonly property MprisPlayer player: {
        const players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing)
                return players[i];
        }
        return players.length > 0 ? players[0] : null;
    }

    readonly property bool playing: player?.playbackState === MprisPlaybackState.Playing

    readonly property int art: 84

    ColumnLayout {
        id: player_
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Metrics.s3

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.s3

            Ui.Card {
                Layout.preferredWidth: root.art
                Layout.preferredHeight: root.art
                radius: Metrics.rCard
                clip: true

                Image {
                    id: cover
                    anchors.fill: parent
                    source: root.player?.trackArtUrl ?? ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.round(root.art * Screen.devicePixelRatio)
                    sourceSize.height: Math.round(root.art * Screen.devicePixelRatio)
                    smooth: true
                    visible: status === Image.Ready
                }

                Ui.Icon {
                    anchors.centerIn: parent
                    name: "music"
                    size: Metrics.iconXl
                    color: Theme.textQuaternary
                    visible: cover.status !== Image.Ready
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                Ui.Label {
                    Layout.fillWidth: true
                    text: root.player?.trackTitle ?? "Nothing playing"
                    role: "headline"
                    elide: Text.ElideRight
                }

                Ui.Label {
                    Layout.fillWidth: true
                    text: root.player?.trackArtist ?? ""
                    role: "callout"
                    elide: Text.ElideRight
                    visible: text !== ""
                }

                Ui.Label {
                    Layout.fillWidth: true
                    text: root.player?.trackAlbum ?? ""
                    role: "caption"
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Metrics.s1
            visible: root.player?.lengthSupported ?? false

            Ui.Slider {
                id: seek
                Layout.fillWidth: true
                maximum: Math.max(1, root.player?.length ?? 1)
                value: root.player?.position ?? 0
                interactive: root.player?.canSeek ?? false
                claimsDrag: false
                onCommitted: at => {
                    if (root.player)
                        root.player.position = at;
                }
            }

            RowLayout {
                Layout.fillWidth: true

                Ui.Label {
                    text: root.clock(root.player?.position ?? 0)
                    role: "caption"
                    numeric: true
                }

                Item {
                    Layout.fillWidth: true
                }

                Ui.Label {
                    text: root.clock(root.player?.length ?? 0)
                    role: "caption"
                    numeric: true
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Metrics.s2

            Item {
                Layout.fillWidth: true
            }

            Ui.Pressable {
                implicitWidth: Metrics.s8
                implicitHeight: Metrics.s8 - Metrics.s1
                radius: Metrics.rControl
                interactive: root.player?.canGoPrevious ?? false
                onClicked: root.player.previous()

                Ui.Icon {
                    anchors.centerIn: parent
                    name: "player-prev"
                    color: Theme.textSecondary
                }
            }

            Ui.Pressable {
                implicitWidth: Metrics.s8 + Metrics.s2
                implicitHeight: Metrics.s8
                radius: Metrics.rCard
                showFill: false
                interactive: root.player?.canTogglePlaying ?? false
                onClicked: root.player.togglePlaying()

                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: parent.pressed ? Theme.fillPress : parent.hovered ? Theme.fillActive : Theme.fillTrack
                    antialiasing: true

                    Behavior on color {
                        Ui.Tint {}
                    }
                }

                Ui.Icon {
                    anchors.centerIn: parent
                    name: root.playing ? "player-pause" : "player-play"
                    size: Metrics.iconLg
                    color: Theme.text
                }
            }

            Ui.Pressable {
                implicitWidth: Metrics.s8
                implicitHeight: Metrics.s8 - Metrics.s1
                radius: Metrics.rControl
                interactive: root.player?.canGoNext ?? false
                onClicked: root.player.next()

                Ui.Icon {
                    anchors.centerIn: parent
                    name: "player-next"
                    color: Theme.textSecondary
                }
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }

    function clock(seconds) {
        const whole = Math.max(0, Math.floor(seconds));
        const minutes = Math.floor(whole / 60);
        const rest = whole % 60;
        return minutes + ":" + (rest < 10 ? "0" : "") + rest;
    }
}
