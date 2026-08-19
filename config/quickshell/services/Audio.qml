pragma Singleton

import QtQuick
import Quickshell.Services.Pipewire

QtObject {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false
    readonly property string sinkName: sink?.description ?? ""

    readonly property bool sourceMuted: source?.audio?.muted ?? false
    readonly property string sourceName: source?.description ?? ""

    readonly property int percent: Math.round(volume * 100)

    readonly property string icon: muted || percent === 0 ? "volume-mute" : percent > 50 ? "volume-high" : "volume-low"

    function setVolume(value) {
        if (sink?.audio)
            sink.audio.volume = Math.max(0, Math.min(1, value));
    }

    function nudge(delta) {
        setVolume(volume + delta);
    }

    function toggleMute() {
        if (sink?.audio)
            sink.audio.muted = !muted;
    }

    function toggleSourceMute() {
        if (source?.audio)
            source.audio.muted = !sourceMuted;
    }

    function announce() {
        Osd.show(icon, muted ? 0 : volume, muted ? "Muted" : percent + "%");
    }

    // Pipewire emits a change when the default sink first binds; that is not a
    // user action and must not flash the OSD at login.
    property bool _bound: false
    onSinkChanged: _bound = false

    readonly property PwObjectTracker _tracker: PwObjectTracker {
        objects: [root.sink, root.source]
    }

    readonly property Connections _sinkEvents: Connections {
        target: root.sink?.audio ?? null

        function onVolumeChanged() {
            if (!root._bound) {
                root._bound = true;
                return;
            }
            root.announce();
        }

        function onMutedChanged() {
            if (root._bound)
                root.announce();
        }
    }
}
