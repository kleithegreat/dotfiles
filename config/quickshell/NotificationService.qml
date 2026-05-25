pragma Singleton
import QtQuick
import Quickshell.Services.Notifications
import "." as Root

QtObject {
    id: root

    property bool doNotDisturb: false
    readonly property int historyCount: historyEntriesModel.count

    property alias popupModel: popupEntriesModel
    property alias historyModel: historyEntriesModel

    property int nextEntryId: 1
    property var rules: ({})
    property var dismissTimers: ({})
    property var trackedNotifications: ({})
    property var closeWatchers: ({})

    function toggleDnd() {
        doNotDisturb = !doNotDisturb;
    }

    function removeNotifPopup(nid) {
        let popupIndex = indexOfEntry(popupEntriesModel, "nid", nid);
        if (popupIndex < 0)
            return;

        removePopupEntryByEntryId(popupEntriesModel.get(popupIndex).entryId, "dismiss");
    }

    function removeHistory(nid) {
        let historyIndex = indexOfEntry(historyEntriesModel, "nid", nid);
        if (historyIndex < 0)
            return;

        historyEntriesModel.remove(historyIndex);
        scheduleRelativeTimeRefresh();
    }

    function removeHistoryEntry(entryId) {
        let historyIndex = indexOfEntry(historyEntriesModel, "entryId", entryId);
        if (historyIndex < 0)
            return;

        historyEntriesModel.remove(historyIndex);
        scheduleRelativeTimeRefresh();
    }

    function clearHistory() {
        historyEntriesModel.clear();
        scheduleRelativeTimeRefresh();
    }

    function matchRule(appName) {
        if (!rules || typeof rules !== "object")
            return null;

        return Object.prototype.hasOwnProperty.call(rules, appName) ? rules[appName] : null;
    }

    function handleNotification(notification) {
        let appName = notification.appName || "Notification";
        let rule = matchRule(appName);
        if (rule && rule.historyOnly)
            return;

        let entry = entryDataFor(notification);
        historyEntriesModel.insert(0, entry);

        let suppressPopup = doNotDisturb || (rule && rule.suppress);
        if (!suppressPopup) {
            popupEntriesModel.insert(0, entry);
            storeTrackedNotification(entry.entryId, notification);

            let timeoutMs = notificationTimeoutMs(notification);
            if (rule && typeof rule.timeout === "number" && isFinite(rule.timeout))
                timeoutMs = Math.max(0, Math.round(rule.timeout));

            createDismissTimer(entry.entryId, timeoutMs);
        }

        scheduleRelativeTimeRefresh();
    }

    function expirePopup(entryId) {
        removePopupEntryByEntryId(entryId, "expire");
    }

    function handleTrackedNotificationClosed(entryId) {
        removePopupEntryByEntryId(entryId, "");
    }

    function entryDataFor(notification) {
        let createdAtMs = Date.now();
        return {
            entryId: nextEntryId++,
            appName: notification.appName || "Notification",
            summary: notification.summary || "",
            body: notification.body || "",
            nid: notification.id,
            createdAtMs: createdAtMs,
            timeStr: relativeTimeString(createdAtMs, createdAtMs)
        };
    }

    function relativeTimeString(createdAtMs, nowMs) {
        let ageMs = Math.max(0, nowMs - createdAtMs);

        if (ageMs < 60 * 1000)
            return "now";
        if (ageMs < 60 * 60 * 1000)
            return Math.floor(ageMs / (60 * 1000)) + "m";
        if (ageMs < 24 * 60 * 60 * 1000)
            return Math.floor(ageMs / (60 * 60 * 1000)) + "h";

        return Math.floor(ageMs / (24 * 60 * 60 * 1000)) + "d";
    }

    function relativeTimeStepMs(ageMs) {
        if (ageMs < 60 * 1000)
            return 5 * 1000;
        if (ageMs < 10 * 60 * 1000)
            return 30 * 1000;

        return 60 * 1000;
    }

    function timeUntilNextRelativeUpdate(createdAtMs, nowMs) {
        let ageMs = Math.max(0, nowMs - createdAtMs);
        let stepMs = relativeTimeStepMs(ageMs);
        let remainder = ageMs % stepMs;
        return remainder === 0 ? stepMs : stepMs - remainder;
    }

    function minDelay(currentMin, candidate) {
        if (candidate < 0)
            return currentMin;
        if (currentMin < 0 || candidate < currentMin)
            return candidate;

        return currentMin;
    }

    function updateModelTimes(model, nowMs) {
        let nextDelay = -1;

        for (let i = 0; i < model.count; i++) {
            let entry = model.get(i);
            if (entry.createdAtMs === undefined)
                continue;

            let timeStr = relativeTimeString(entry.createdAtMs, nowMs);
            if (entry.timeStr !== timeStr)
                model.setProperty(i, "timeStr", timeStr);

            nextDelay = minDelay(nextDelay, timeUntilNextRelativeUpdate(entry.createdAtMs, nowMs));
        }

        return nextDelay;
    }

    // One adaptive timer keeps relative timestamps fresh across both models.
    function scheduleRelativeTimeRefresh() {
        let nowMs = Date.now();
        let nextDelay = -1;

        nextDelay = minDelay(nextDelay, updateModelTimes(historyEntriesModel, nowMs));
        nextDelay = minDelay(nextDelay, updateModelTimes(popupEntriesModel, nowMs));

        if (nextDelay < 0) {
            relativeTimeTimer.stop();
            return;
        }

        relativeTimeTimer.interval = nextDelay;
        relativeTimeTimer.restart();
    }

    function notificationTimeoutMs(notification) {
        if (notification.expireTimeout > 0)
            return Math.round(notification.expireTimeout * 1000);

        return Root.Theme.notifTimeout;
    }

    function storeTrackedNotification(entryId, notification) {
        notification.tracked = true;
        trackedNotifications[entryId] = notification;

        let watcher = notificationCloseWatcherComponent.createObject(root, {
            trackedNotification: notification,
            trackedEntryId: entryId
        });

        if (watcher)
            closeWatchers[entryId] = watcher;
    }

    function clearTrackedNotification(entryId) {
        if (trackedNotifications[entryId] !== undefined)
            delete trackedNotifications[entryId];
        if (closeWatchers[entryId] !== undefined)
            delete closeWatchers[entryId];
    }

    function takeTrackedNotification(entryId) {
        let notification = trackedNotifications[entryId] || null;
        let watcher = closeWatchers[entryId] || null;

        if (watcher)
            watcher.destroy();

        clearTrackedNotification(entryId);
        return notification;
    }

    function createDismissTimer(entryId, intervalMs) {
        destroyDismissTimer(entryId);

        let timer = dismissTimerComponent.createObject(root, {
            targetEntryId: entryId,
            interval: intervalMs
        });

        if (timer)
            dismissTimers[entryId] = timer;
    }

    function destroyDismissTimer(entryId) {
        let timer = dismissTimers[entryId];
        if (!timer)
            return;

        timer.destroy();
        delete dismissTimers[entryId];
    }

    function indexOfEntry(model, roleName, value) {
        for (let i = 0; i < model.count; i++) {
            if (model.get(i)[roleName] === value)
                return i;
        }

        return -1;
    }

    function removePopupEntryByEntryId(entryId, closeAction) {
        let popupIndex = indexOfEntry(popupEntriesModel, "entryId", entryId);
        if (popupIndex >= 0)
            popupEntriesModel.remove(popupIndex);

        destroyDismissTimer(entryId);

        let notification = null;
        if (closeAction !== "")
            notification = takeTrackedNotification(entryId);
        else
            clearTrackedNotification(entryId);

        if (notification) {
            if (closeAction === "expire")
                notification.expire();
            else if (closeAction === "dismiss")
                notification.dismiss();
        }

        scheduleRelativeTimeRefresh();
    }

    property NotificationServer server: NotificationServer {
        id: server
        bodySupported: true
        bodyImagesSupported: true
        imageSupported: true
        keepOnReload: false
        onNotification: (notification) => root.handleNotification(notification)
    }

    property ListModel popupEntriesModel: ListModel { id: popupEntriesModel }
    property ListModel historyEntriesModel: ListModel { id: historyEntriesModel }

    property Timer relativeTimeTimer: Timer {
        id: relativeTimeTimer
        repeat: false
        onTriggered: root.scheduleRelativeTimeRefresh()
    }

    property Component dismissTimerComponent: Component {
        id: dismissTimerComponent

        Timer {
            required property int targetEntryId
            running: true
            repeat: false
            onTriggered: root.expirePopup(targetEntryId)
        }
    }

    property Component notificationCloseWatcherComponent: Component {
        id: notificationCloseWatcherComponent

        Connections {
            required property var trackedNotification
            required property int trackedEntryId
            target: trackedNotification

            function onClosed() {
                root.handleTrackedNotificationClosed(trackedEntryId);
                this.destroy();
            }
        }
    }
}
