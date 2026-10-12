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
        if (!sink?.audio)
            return;
        _wrote = Date.now();
        sink.audio.volume = Math.max(0, Math.min(1, value));
    }

    function toggleMute() {
        if (!sink?.audio)
            return;
        _wrote = Date.now();
        sink.audio.muted = !muted;
    }

    function toggleSourceMute() {
        if (source?.audio)
            source.audio.muted = !sourceMuted;
    }

    // The shell's own writes come back as change events a moment later, after
    // the control that made them has let go; only changes from outside it
    // (keys, other apps) are worth an OSD.
    property real _wrote: 0

    function announce() {
        if (Date.now() - _wrote < 400)
            return;
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
