pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris

// The connected pair and the nearest open case, pushed by the daemon
// ([[airpods]]). Pairing itself goes through Bluetooth's write path.
QtObject {
    id: root

    property var link: null
    property var nearby: null

    readonly property bool connected: link !== null
    readonly property var battery: link ? link.battery : nearby ? nearby.battery : null
    // A pair reports these only if it has them.
    readonly property bool hasNoise: (link?.noise ?? null) !== null
    readonly property bool hasAwareness: (link?.awareness ?? null) !== null
    readonly property string noise: writes.value("noise", link?.noise ?? "")
    readonly property bool awareness: writes.value("awareness", link?.awareness ?? false)

    readonly property var noiseModes: [
        { value: "off", label: "Off" },
        { value: "transparency", label: "Transparency" },
        { value: "adaptive", label: "Adaptive" },
        { value: "anc", label: "Cancellation" }
    ]

    // The setup card: "" · status · connect · hold · connecting · done · failed
    property string card: ""
    property string model: ""
    property var _candidate: null

    function setNoise(mode) {
        writes.set("noise", mode, ["desktopctl", "airpods", "noise", mode]);
    }

    function setAwareness(on) {
        writes.set("awareness", on, ["desktopctl", "airpods", "awareness", String(on)]);
    }

    function connectCase() {
        const known = nearby?.paired ? Bluetooth.devices.find(device => device.address === nearby.paired) : undefined;
        if (known) {
            _candidate = known;
            card = "connecting";
            known.connect();
        } else {
            _candidate = null;
            card = "hold";
            Bluetooth.setDiscovering(true);
        }
        deadline.restart();
    }

    function dismiss() {
        if (_candidate?.pairing)
            _candidate.cancelPair();
        if (card === "hold" || card === "connecting")
            Bluetooth.setDiscovering(false);
        _candidate = null;
        card = "";
    }

    function _ingest(status) {
        const wasOpen = nearby?.lid_open ?? false;
        _ears(status.link);
        link = status.link;
        nearby = status.nearby;
        writes.settle({ noise: link?.noise, awareness: link?.awareness });

        const open = nearby?.lid_open ?? false;
        if (open && !wasOpen && card === "") {
            model = nearby.model;
            card = nearby.paired ? "status" : "connect";
        } else if (!open && (card === "status" || card === "connect")) {
            card = "";
        }
        _settle();
    }

    function _settle() {
        if (card !== "connecting" || !(connected || _candidate?.connected))
            return;
        Bluetooth.setDiscovering(false);
        deadline.stop();
        card = "done";
    }

    // Taking a pod out pauses what is playing; putting it back resumes it.
    property int _inEar: 0
    property var _paused: null

    function _ears(next) {
        if (!next) {
            _inEar = 0;
            _paused = null;
            return;
        }
        const inEar = (next.ears ?? []).filter(pod => pod === "in_ear").length;
        if (inEar < _inEar) {
            const playing = Mpris.players.values.find(player => player.playbackState === MprisPlaybackState.Playing);
            if (playing) {
                playing.pause();
                _paused = playing;
            }
        } else if (inEar > _inEar && _paused) {
            _paused.play();
            _paused = null;
        }
        _inEar = inEar;
    }

    readonly property WriteQueue _writes: WriteQueue {
        id: writes
        failureText: "AirPods change failed"
    }

    readonly property Connections _events: Connections {
        target: Desktopctl
        function onAirpodsChanged(status) {
            root._ingest(status);
        }
    }

    // The case's own advert carries no BR/EDR address; a discoverable pair
    // shows up by name once its setup button is held.
    readonly property Connections _discovery: Connections {
        target: Bluetooth
        enabled: root.card === "hold"
        function onDiscoveredChanged() {
            const found = Bluetooth.discovered.find(device => device.name.indexOf("AirPods") >= 0);
            if (!found)
                return;
            root._candidate = found;
            root.card = "connecting";
            found.pair();
            deadline.restart();
        }
    }

    readonly property Connections _pairing: Connections {
        target: root._candidate
        function onPairedChanged() {
            if (!root._candidate.paired)
                return;
            root._candidate.trusted = true;
            root._candidate.connect();
        }
        function onConnectedChanged() {
            root._settle();
        }
    }

    readonly property Timer _deadline: Timer {
        id: deadline
        interval: root.card === "hold" ? 60000 : 30000
        onTriggered: {
            if (root.card !== "hold" && root.card !== "connecting")
                return;
            Bluetooth.setDiscovering(false);
            root.card = "failed";
        }
    }
}
