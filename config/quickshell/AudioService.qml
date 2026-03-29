pragma Singleton
import QtQuick
import Quickshell.Services.Pipewire
import "." as Root

QtObject {
    id: root

    property bool suppressOsd: false

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sinkAudio: sink?.audio ?? null
    readonly property real volume: sinkAudio?.volume ?? 0
    readonly property bool muted: sinkAudio?.muted ?? false
    readonly property string sinkDescription: sink?.description ?? ""

    property bool osdVolInit: false
    property bool showOsd: false
    property real osdValue: 0
    property string osdIcon: ""
    property string osdLabel: ""
    property alias osdTimer: osdHideTimer

    function clampVolume(value) {
        return Math.max(0, Math.min(1, value));
    }

    function incrementVolume(step) {
        if (step === undefined)
            step = 0.05;

        setVolume(volume + step);
    }

    function decrementVolume(step) {
        if (step === undefined)
            step = 0.05;

        setVolume(volume - step);
    }

    function setVolume(value) {
        if (!sinkAudio)
            return;

        sinkAudio.volume = clampVolume(value);
    }

    function toggleMute() {
        if (!sinkAudio)
            return;

        sinkAudio.muted = !muted;
    }

    function volumeIconFor(percent, isMuted) {
        if (isMuted || percent === 0)
            return "󰝟";
        if (percent > 66)
            return "󰕾";
        if (percent > 33)
            return "󰖀";
        return "󰕿";
    }

    function showOsdState(value, label, icon) {
        osdValue = Math.max(0, Math.min(value, 100));
        osdLabel = label;
        osdIcon = icon;
        showOsd = true;
        osdHideTimer.restart();
    }

    function showVolumeOsd() {
        if (!sinkAudio || suppressOsd)
            return;

        let percent = Math.round(volume * 100);
        showOsdState(muted ? 0 : percent, muted ? "Muted" : percent + "%", volumeIconFor(percent, muted));
    }

    onSinkAudioChanged: osdVolInit = false

    property PwObjectTracker sinkTracker: PwObjectTracker {
        objects: [root.sink]
    }

    property Connections sinkConnections: Connections {
        target: root.sinkAudio

        function onVolumeChanged() {
            if (!root.osdVolInit) {
                root.osdVolInit = true;
                return;
            }

            if (root.suppressOsd)
                return;

            root.showVolumeOsd();
        }

        function onMutedChanged() {
            if (!root.osdVolInit || root.suppressOsd)
                return;

            root.showVolumeOsd();
        }
    }

    property Timer osdHideTimer: Timer {
        id: osdHideTimer
        interval: Root.Theme.osdTimeout
        onTriggered: root.showOsd = false
    }
}
