pragma Singleton

import QtQuick
import Quickshell.Services.Pipewire

QtObject {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    readonly property real volume: sink?.audio?.volume ?? 0
    readonly property bool muted: sink?.audio?.muted ?? false

    readonly property bool sourceMuted: source?.audio?.muted ?? false
    readonly property string sourceName: source?.description ?? ""

    readonly property int percent: Math.round(volume * 100)

    // Devices, not application streams. A Bluetooth pair joins once connected.
    readonly property var sinks: Pipewire.nodes.values.filter(node => node.isSink && !node.isStream && node.audio !== null)

    function useSink(node) {
        Pipewire.preferredDefaultAudioSink = node;
    }

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

    // The shell's own writes echo back after the control lets go; only outside changes earn an OSD.
    property real _wrote: 0

    function announce() {
        if (Date.now() - _wrote < 400)
            return;
        Osd.show(icon, muted ? 0 : volume, muted ? "Muted" : percent + "%");
    }

    // The default sink's first bind emits a change, which must not flash the OSD at login.
    property bool _bound: false
    onSinkChanged: {
        _bound = false;
        bindSettle.restart();
    }

    readonly property Timer _bindSettle: Timer {
        id: bindSettle
        interval: 150
        running: root.sink !== null && !root._bound
        onTriggered: root._bound = true
    }

    readonly property PwObjectTracker _tracker: PwObjectTracker {
        objects: [root.source].concat(root.sinks)
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
            if (!root._bound) {
                root._bound = true;
                return;
            }
            root.announce();
        }
    }
}
