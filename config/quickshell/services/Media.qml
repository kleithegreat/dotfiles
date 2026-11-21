pragma Singleton

import QtQuick
import Quickshell.Services.Mpris

QtObject {
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
}
