pragma Singleton

import QtQuick
import Quickshell

// AirDrop as the daemon runs it over Owly ([[airdrop]]): visibility, offers
// coming in, and the share going out.
QtObject {
    id: root

    // How Owly runs the radio here; "" when AirDrop cannot use it.
    property string mode: ""
    property bool busy: false
    property int visibleUntil: 0
    property var requests: []
    property var share: null
    // What arrived last, until the card is dismissed: { sender, paths, urls }.
    property var delivered: null

    readonly property bool available: mode !== ""
    readonly property bool visible_: visibleUntil > 0
    // Exclusive radios take the station off its network while AirDrop holds them.
    readonly property bool pausesWifi: mode !== "" && mode !== "shared"
    readonly property var request: requests.length > 0 ? requests[0] : null
    property real _now: Date.now() / 1000
    readonly property int minutesLeft: Math.max(1, Math.ceil((visibleUntil - _now) / 60))

    function setVisible(on) {
        writes.run(["desktopctl", "airdrop", "visible", String(on)]);
    }

    function answer(id, accept) {
        writes.run(["desktopctl", "airdrop", "answer", String(id), String(accept)]);
    }

    function send(receiver) {
        writes.run(["desktopctl", "airdrop", "send", receiver]);
    }

    function cancel() {
        writes.run(["desktopctl", "airdrop", "cancel"]);
    }

    function dismissDelivered() {
        delivered = null;
    }

    function showDelivered() {
        const first = delivered?.paths?.[0];
        if (first)
            Quickshell.execDetached(["busctl", "--user", "call", "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1", "org.freedesktop.FileManager1", "ShowItems", "ass", "1", "file://" + encodeURI(first), ""]);
        delivered = null;
    }

    function openDelivered() {
        const url = delivered?.urls?.[0];
        if (url)
            Qt.openUrlExternally(url);
        delivered = null;
    }

    readonly property WriteQueue _writes: WriteQueue {
        id: writes
        failureText: "AirDrop failed"
    }

    readonly property Connections _events: Connections {
        target: Desktopctl
        function onAirdropChanged(status) {
            root.mode = status.mode ?? "";
            root.busy = status.busy;
            root.visibleUntil = status.visible_until ?? 0;
            root.requests = status.requests ?? [];
            root.share = status.share ?? null;
            root._now = Date.now() / 1000;
        }
        function onAirdropReceived(data) {
            root.delivered = data;
        }
        function onAirdropFailed(data) {
            Toast.error(data.reason || "AirDrop failed");
        }
    }

    readonly property Timer _clock: Timer {
        interval: 15000
        repeat: true
        running: root.visible_
        onTriggered: root._now = Date.now() / 1000
    }
}
