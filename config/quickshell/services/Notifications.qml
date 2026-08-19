pragma Singleton

import QtQuick
import Quickshell.Services.Notifications

// Banners are *rendered from* the server's tracked set rather than mirrored into
// a parallel model. Mirroring is what forced the old service to create a
// Connections object per notification just to learn that one had been closed
// behind its back; membership of `server.trackedNotifications` already is that
// signal. History is our own list because it has to outlive the notification.
QtObject {
    id: root

    property bool dnd: false

    readonly property int historyLimit: 200
    readonly property int bannerLimit: 4
    readonly property int defaultDwell: 5000

    readonly property list<Notification> banners: {
        const live = server.trackedNotifications.values;
        const shown = [];
        for (let i = live.length - 1; i >= 0 && shown.length < bannerLimit; i--)
            shown.push(live[i]);
        return shown;
    }

    readonly property int historyCount: history.count

    property var _deadlines: ({})

    function toggleDnd() {
        dnd = !dnd;
        if (dnd)
            dismissAll();
    }

    function dismiss(notification) {
        if (notification)
            notification.dismiss();
    }

    function dismissAll() {
        const live = server.trackedNotifications.values.slice();
        for (let i = 0; i < live.length; i++)
            live[i].dismiss();
    }

    function forget(entryId) {
        for (let i = 0; i < history.count; i++) {
            if (history.get(i).entryId === entryId) {
                history.remove(i);
                return;
            }
        }
    }

    function clearHistory() {
        history.clear();
    }

    function ageLabel(createdAt) {
        const age = Math.max(0, Date.now() - createdAt);
        if (age < 60000)
            return "now";
        if (age < 3600000)
            return Math.floor(age / 60000) + "m";
        if (age < 86400000)
            return Math.floor(age / 3600000) + "h";
        return Math.floor(age / 86400000) + "d";
    }

    property int _nextId: 1

    function _receive(notification) {
        history.insert(0, {
            entryId: _nextId++,
            appName: notification.appName || "Notification",
            summary: notification.summary || "",
            body: notification.body || "",
            image: notification.image || "",
            createdAt: Date.now(),
            age: "now"
        });
        while (history.count > historyLimit)
            history.remove(history.count - 1);

        _restamp();

        if (dnd)
            return;

        notification.tracked = true;
        const dwell = notification.expireTimeout > 0 ? Math.round(notification.expireTimeout * 1000) : defaultDwell;
        const next = Object.assign({}, _deadlines);
        next[notification.id] = Date.now() + dwell;
        _deadlines = next;
        _arm();
    }

    // One timer for every banner, set to the nearest deadline, instead of one
    // timer object per notification.
    function _arm() {
        let soonest = -1;
        const live = server.trackedNotifications.values;
        for (let i = 0; i < live.length; i++) {
            const due = _deadlines[live[i].id];
            if (due !== undefined && (soonest < 0 || due < soonest))
                soonest = due;
        }

        if (soonest < 0) {
            expiry.stop();
            return;
        }

        expiry.interval = Math.max(50, soonest - Date.now());
        expiry.restart();
    }

    function _sweep() {
        const now = Date.now();
        const live = server.trackedNotifications.values.slice();
        const next = Object.assign({}, _deadlines);
        for (let i = 0; i < live.length; i++) {
            const due = next[live[i].id];
            if (due !== undefined && due <= now) {
                delete next[live[i].id];
                live[i].expire();
            }
        }
        _deadlines = next;
        _arm();
    }

    function _restamp() {
        for (let i = 0; i < history.count; i++)
            history.setProperty(i, "age", ageLabel(history.get(i).createdAt));
    }

    readonly property NotificationServer _server: NotificationServer {
        id: server
        bodySupported: true
        bodyImagesSupported: true
        imageSupported: true
        actionsSupported: true
        keepOnReload: false
        onNotification: notification => root._receive(notification)
    }

    readonly property ListModel history: ListModel {
        id: history
    }

    readonly property Timer _expiry: Timer {
        id: expiry
        onTriggered: root._sweep()
    }

    // Relative stamps only ever need minute resolution once anything is a minute
    // old, and nothing in the drawer is watched closely enough to need better.
    readonly property Timer _restamper: Timer {
        interval: 30000
        running: history.count > 0
        repeat: true
        onTriggered: root._restamp()
    }
}
