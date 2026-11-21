pragma Singleton

import QtQuick
import Quickshell.Services.Mpris

// Pushed by the daemon ([[airpods]]); pairing goes through Bluetooth's write path.
QtObject {
    id: root

    property var link: null
    property var nearby: null
    property string _reach: "close"

    readonly property bool connected: link !== null
    readonly property var battery: link ? link.battery : nearby ? nearby.battery : null
    // A pair reports these only if it has them.
    readonly property bool hasNoise: (link?.noise ?? null) !== null
    readonly property bool hasAwareness: (link?.awareness ?? null) !== null
    readonly property string noise: writes.value("noise", link?.noise ?? "")
    readonly property bool awareness: writes.value("awareness", link?.awareness ?? false)
    // How close an open case must be to raise the card ([[airpods]]).
    readonly property string reach: writes.value("reach", _reach)
    readonly property var reaches: [
        { value: "off", label: "Off" },
        { value: "close", label: "Next to this computer" },
        { value: "near", label: "Within reach" }
    ]

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

    function setReach(value) {
        writes.set("reach", value, ["desktopctl", "airpods", "reach", value]);
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
            Bluetooth.seek("airpods", true);
            _tryPairDiscovered();
        }
        deadline.restart();
    }

    function _tryPairDiscovered() {
        if (card !== "hold")
            return;
        const found = Bluetooth.discovered.find(device => device.name.indexOf("AirPods") >= 0);
        if (!found)
            return;
        _candidate = found;
        card = "connecting";
        found.pair();
        deadline.restart();
    }

    function dismiss() {
        if (_candidate?.pairing)
            _candidate.cancelPair();
        Bluetooth.seek("airpods", false);
        _candidate = null;
        card = "";
    }

    function _ingest(status) {
        const wasOpen = nearby?.lid_open ?? false;
        _ears(status.link);
        link = status.link;
        nearby = status.nearby;
        _reach = status.reach ?? "close";
        writes.settle({ noise: link?.noise, awareness: link?.awareness, reach: _reach });

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
        Bluetooth.seek("airpods", false);
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
            const playing = Media.playing ? Media.player : null;
            if (playing) {
                playing.pause();
                _paused = playing;
            }
        } else if (inEar > _inEar && _paused) {
            if (Mpris.players.values.indexOf(_paused) >= 0 && _paused.canPlay)
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

    // A pair is found by name, not by the advert's address ([[airpods]]).
    readonly property Connections _discovery: Connections {
        target: Bluetooth
        enabled: root.card === "hold"
        function onDiscoveredChanged() {
            root._tryPairDiscovered();
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
            Bluetooth.seek("airpods", false);
            root.card = "failed";
        }
    }
}
