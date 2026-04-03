import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components" as Components
import "settings" as Settings

FocusScope {
    id: settingsPop
    property bool active: false
    signal close()
    property bool closing: false
    property bool contentLoaded: false
    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: settingsContentLoader.item
    readonly property Item focusTarget: settingsPop
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    /*
    Legacy per-popup PanelWindow wrapper retained during the overlay-host migration:
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
        anchors.fill: parent; onClicked: settingsPop.close()
        focus: settingsPop.active
        Keys.onEscapePressed: settingsPop.close()
    }
    */

    // ── State ──
    property var themeState: ({})
    property var colorSchemes: []
    property var colorFamilies: []
    property var presets: []
    property var wallpapers: []
    property bool directoryBrowserOpen: false
    property string directoryBrowserPath: "/home/kevin/repos/dotfiles/wallpapers"
    property var directoryBrowserEntries: []
    property var monoFontSizeOffsetTargets: [
        { label: "Alacritty", key: "alacritty_mono_font_size_offset" },
        { label: "Ghostty", key: "ghostty_mono_font_size_offset" },
        { label: "GTK", key: "gtk_mono_font_size_offset" },
        { label: "Qt", key: "qt_mono_font_size_offset" },
        { label: "VS Code", key: "vscode_mono_font_size_offset" }
    ]
    property int selectedCategory: 0
    property int systemCategoryCount: 7
    property string wallpaperDir: "/home/kevin/repos/dotfiles/wallpapers"
    property var categoryNames: ["Network", "Bluetooth", "Audio", "Display", "Power", "Notifications", "Screen Time", "Presets", "Colors", "Fonts", "Wallpaper", "Icons & Cursors", "Hyprland"]
    property var categoryIcons: ["󰖩", "󰂯", "󰕾", "󰍹", "⚡", "󰂚", "󱑎", "󰒓", "󰏘", "󰛖", "󰋩", "󰍽", "󰖯"]
    property var hyprOptionInfo: ({
        "general:gaps_in": { label: "Inner gaps", type: "int", fallback: 4, minimum: 0, step: 1, stateKey: "hypr_gaps_in" },
        "general:gaps_out": { label: "Outer gaps", type: "int", fallback: 6, minimum: 0, step: 1, stateKey: "hypr_gaps_out" },
        "general:border_size": { label: "Border size", type: "int", fallback: 0, minimum: 0, step: 1, stateKey: "hypr_border_size" },
        "decoration:rounding": { label: "Rounding", type: "int", fallback: 8, minimum: 0, step: 1, stateKey: "hypr_rounding" },
        "decoration:blur:enabled": { label: "Enable blur", type: "bool", fallback: false, stateKey: "hypr_blur_enabled" },
        "decoration:blur:size": { label: "Blur size", type: "int", fallback: 3, minimum: 1, step: 1, stateKey: "hypr_blur_size" },
        "decoration:blur:passes": { label: "Blur passes", type: "int", fallback: 4, minimum: 1, step: 1, stateKey: "hypr_blur_passes" },
        "animations:enabled": { label: "Enable animations", type: "bool", fallback: true, stateKey: "hypr_animations_enabled" }
    })
    property var hyprGeneralOptions: ["general:gaps_in", "general:gaps_out", "general:border_size"]
    property var hyprDecorationOptions: ["decoration:rounding"]
    property var hyprBlurOptions: ["decoration:blur:size", "decoration:blur:passes"]
    property var hyprManagedOptions: [
        "general:gaps_in",
        "general:gaps_out",
        "general:border_size",
        "decoration:rounding",
        "decoration:blur:enabled",
        "decoration:blur:size",
        "decoration:blur:passes",
        "animations:enabled"
    ]
    property var hyprDraftState: ({})
    property var hyprDirtyValues: ({})
    property var hyprDirtyOrder: []
    property string hyprRuntimeError: ""
    property bool hyprApplyQueued: false
    property var hyprNotificationQueue: []
    property string presetCommandError: ""
    property int presetMutationToken: 0
    property bool themeStateReloadPending: false

    function preparePanelForOpen() {
        let item = settingsContentLoader.item;
        if (!item)
            return false;

        item.opacity = 0;
        item.scale = 0.92;
        return true;
    }

    onActiveChanged: {
        if (active) {
            forceActiveFocus();
            contentLoaded = true;
            loadState();
            refreshSystemServices();
            if (preparePanelForOpen())
                settingsOpenAnim.start();
        }
        else if (!closing) {
            closeDirectoryBrowser();
            if (settingsContentLoader.item) {
                closing = true;
                settingsCloseAnim.start();
            } else {
                closing = false;
            }
        }
    }

    // ── Data loading ──
    function refreshSystemServices() {
        NetworkService.scan();
        NetworkService.loadKnown();
        VpnService.refresh();
        BluetoothService.clearConnectError();
        BluetoothService.refresh();
        BrightnessService.refresh();
        DisplayService.refresh();
        PowerProfileService.detect();
        PowerProfileService.detectChargeLimit();
    }

    function loadThemeState() {
        if (stateProc.running) {
            themeStateReloadPending = true;
            return;
        }

        themeStateReloadPending = false;
        stateProc.buf = "";
        stateProc.running = true;
    }

    function loadState() {
        loadThemeState();
        refreshColorFamilies();
        refreshPresets();
        refreshWallpapers();
    }

    Process {
        id: stateProc; command: ["desktopctl", "theme", "status", "--json"]; running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { stateProc.buf += line; } }
        onExited: {
            try {
                settingsPop.themeState = JSON.parse(buf);
                settingsPop.syncHyprDraftState();
            } catch(e) {}
            buf = "";

            if (settingsPop.themeStateReloadPending)
                settingsPop.loadThemeState();
        }
    }

    Process {
        id: listColorsProc; running: false
        command: ["desktopctl", "theme", "list-schemes", "--json"]
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { listColorsProc.buf += line; } }
        onExited: {
            let items = [];
            try {
                let parsed = JSON.parse(buf);
                if (Array.isArray(parsed))
                    items = parsed;
            } catch(e) {}

            let schemes = [];
            let result = [];
            for (let i = 0; i < items.length; i++) {
                let d = items[i];
                schemes.push(d.schemeName);
                result.push({
                    schemeName: d.schemeName,
                    family: d.family || d.schemeName,
                    variant: d.variant || "dark",
                    bg: d.bg || "#282828", fg: d.fg || "#ebdbb2",
                    accent: d.accent || "#458588", red: d.red || "#cc241d",
                    green: d.green || "#98971a", blue: d.blue || "#458588",
                    yellow: d.yellow || "#d79921", purple: d.purple || "#b16286"
                });
            }
            settingsPop.colorSchemes = schemes;
            settingsPop.colorFamilies = result;
            buf = "";
        }
    }

    Process {
        id: listPresetsProc; running: false
        command: ["desktopctl", "theme", "list-presets", "--json"]
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { listPresetsProc.buf += line; } }
        onExited: {
            let items = [];
            try {
                let parsed = JSON.parse(buf);
                if (Array.isArray(parsed))
                    items = parsed;
            } catch(e) {}
            settingsPop.presets = items;
            buf = "";
        }
    }

    Process {
        id: listWallpapersProc; running: false
        command: ["bash", "-c", "ls -- \"$1\" 2>/dev/null || true", "_", settingsPop.wallpaperDir]
        property var items: []
        stdout: SplitParser { onRead: (line) => { let t = line.trim(); if (t !== "") listWallpapersProc.items.push(t); } }
        onExited: { settingsPop.wallpapers = items; items = []; }
    }

    Process {
        id: listDirectoriesProc; running: false
        command: [
            "bash",
            "-c",
            "find \"$1\" -mindepth 1 -maxdepth 1 -type d -printf '%f\\n' 2>/dev/null | sort -f || true",
            "_",
            settingsPop.directoryBrowserPath
        ]
        property var items: []
        stdout: SplitParser { onRead: (line) => { let t = line.trim(); if (t !== "") listDirectoriesProc.items.push(t); } }
        onExited: { settingsPop.directoryBrowserEntries = items; items = []; }
    }

    Process {
        id: hyprApplyProc
        running: false
        property string buf: ""
        property string pendingStateKey: ""
        property string pendingValue: ""
        property string pendingLabel: ""
        stdout: SplitParser { onRead: (line) => { hyprApplyProc.buf += line; } }
        stderr: SplitParser { onRead: (line) => { hyprApplyProc.buf += line; } }
        onExited: (code, status) => {
            let output = (buf || "").trim();
            if (code !== 0) {
                settingsPop.hyprRuntimeError = output !== "" ? output : "Failed to update Hyprland";
                if (pendingLabel !== "")
                    settingsPop.queueHyprNotification("Hyprland update failed", settingsPop.hyprNotificationBody([pendingLabel], settingsPop.hyprRuntimeError));
                settingsPop.syncHyprDraftState();
            } else {
                settingsPop.hyprRuntimeError = "";
                if (pendingLabel !== "")
                    settingsPop.queueHyprNotification("Hyprland updated", pendingLabel);
                settingsPop.loadThemeState();
            }

            buf = "";
            pendingStateKey = "";
            pendingValue = "";
            pendingLabel = "";

            if (settingsPop.hyprApplyQueued || settingsPop.hyprDirtyOrder.length > 0) {
                settingsPop.hyprApplyQueued = false;
                hyprWriteTimer.restart();
            }
        }
    }

    Process {
        id: hyprNotifyProc
        running: false
        stdout: SplitParser { onRead: (_) => {} }
        stderr: SplitParser { onRead: (_) => {} }
        onExited: settingsPop.runNextHyprNotification()
    }

    Timer {
        id: hyprWriteTimer
        interval: 120
        repeat: false
        onTriggered: settingsPop.flushHyprStateWrites()
    }

    // ── Helper functions ──
    function familyDisplayName(name) {
        if (name === "tokyonight") return "Tokyo Night";
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function refreshWallpapers() {
        listWallpapersProc.items = [];
        listWallpapersProc.running = true;
    }

    function refreshColorFamilies() {
        listColorsProc.buf = "";
        listColorsProc.running = true;
    }

    function refreshPresets() {
        listPresetsProc.buf = "";
        listPresetsProc.running = true;
    }

    function refreshDirectoryBrowser() {
        listDirectoriesProc.items = [];
        listDirectoriesProc.running = true;
    }

    function parentDirectory(path) {
        if (!path || path === "/") return "/";
        let normalized = path;
        while (normalized.length > 1 && normalized.endsWith("/"))
            normalized = normalized.slice(0, normalized.length - 1);
        let slash = normalized.lastIndexOf("/");
        return slash <= 0 ? "/" : normalized.slice(0, slash);
    }

    function joinPath(base, name) {
        return base === "/" ? "/" + name : base + "/" + name;
    }

    function openDirectoryBrowser() {
        settingsPop.directoryBrowserPath = settingsPop.wallpaperDir;
        settingsPop.directoryBrowserOpen = true;
        refreshDirectoryBrowser();
    }

    function closeDirectoryBrowser() {
        settingsPop.directoryBrowserOpen = false;
        settingsPop.directoryBrowserPath = settingsPop.wallpaperDir;
        settingsPop.directoryBrowserEntries = [];
    }

    function browseDirectory(name) {
        let nextPath = name === ".."
            ? parentDirectory(settingsPop.directoryBrowserPath)
            : joinPath(settingsPop.directoryBrowserPath, name);
        settingsPop.directoryBrowserPath = nextPath;
        refreshDirectoryBrowser();
    }

    function monoFontBaseSize() {
        return settingsPop.themeState.mono_font_size || 11;
    }

    function monoFontSizeOffset(key) {
        let value = settingsPop.themeState[key];
        return value === undefined || value === null ? 0 : value;
    }

    function effectiveMonoFontSize(key) {
        return monoFontBaseSize() + monoFontSizeOffset(key);
    }

    function minimumMonoFontSizeOffset() {
        let minOffset = 0;
        for (let i = 0; i < settingsPop.monoFontSizeOffsetTargets.length; i++) {
            let offset = monoFontSizeOffset(settingsPop.monoFontSizeOffsetTargets[i].key);
            if (offset < minOffset)
                minOffset = offset;
        }
        return minOffset;
    }

    function formatSignedNumber(value) {
        return value > 0 ? "+" + value : String(value);
    }

    function adjustMonoFontSizeOffset(key, delta) {
        let next = monoFontSizeOffset(key) + delta;
        if (monoFontBaseSize() + next < 1)
            return;
        settingsPop.runSet(key, String(next));
    }

    function confirmDirectoryBrowser() {
        settingsPop.wallpaperDir = settingsPop.directoryBrowserPath;
        settingsPop.directoryBrowserOpen = false;
        settingsPop.directoryBrowserEntries = [];
        refreshWallpapers();
    }

    function cloneMap(source) {
        let next = {};
        let keys = Object.keys(source || {});

        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = source[keys[i]];

        return next;
    }

    function hyprOptionMeta(option) {
        return settingsPop.hyprOptionInfo[option] || {};
    }

    function hyprStateKey(option) {
        return settingsPop.hyprOptionMeta(option).stateKey || "";
    }

    function hyprThemeStateValue(stateKey, fallback) {
        let value = settingsPop.themeState[stateKey];
        return value === undefined || value === null ? fallback : value;
    }

    function hyprStateValue(stateKey, fallback) {
        let value = settingsPop.hyprDraftState[stateKey];
        if (value !== undefined && value !== null)
            return value;

        return settingsPop.hyprThemeStateValue(stateKey, fallback);
    }

    function syncHyprDraftState() {
        let nextDraft = settingsPop.cloneMap(settingsPop.hyprDraftState);
        let dirty = settingsPop.hyprDirtyValues || {};
        let pendingKey = hyprApplyProc.pendingStateKey;

        for (let i = 0; i < settingsPop.hyprManagedOptions.length; i++) {
            let option = settingsPop.hyprManagedOptions[i];
            let stateKey = settingsPop.hyprStateKey(option);
            if (stateKey === "" || dirty[stateKey] !== undefined || stateKey === pendingKey)
                continue;

            nextDraft[stateKey] = settingsPop.hyprThemeStateValue(stateKey, settingsPop.hyprOptionMeta(option).fallback);
        }

        settingsPop.hyprDraftState = nextDraft;
    }

    function hyprNotificationBody(labels, detail) {
        let text = "";

        if ((labels || []).length > 0) {
            if (labels.length <= 3)
                text = labels.join(", ");
            else
                text = labels.slice(0, 3).join(", ") + " +" + String(labels.length - 3) + " more";
        }

        if (detail && detail !== "")
            text = text !== "" ? text + "\n" + detail : detail;

        return text;
    }

    function queueHyprNotification(summary, body) {
        settingsPop.hyprNotificationQueue.push({
            summary: summary,
            body: body || ""
        });

        if (!hyprNotifyProc.running)
            settingsPop.runNextHyprNotification();
    }

    function runNextHyprNotification() {
        if (hyprNotifyProc.running || settingsPop.hyprNotificationQueue.length === 0)
            return;

        let next = settingsPop.hyprNotificationQueue.shift();
        hyprNotifyProc.command = [
            "busctl",
            "--user",
            "call",
            "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications",
            "Notify",
            "susssasa{sv}i",
            "Settings",
            "0",
            "",
            next.summary,
            next.body,
            "0",
            "0",
            "1600"
        ];
        hyprNotifyProc.running = true;
    }

    function removeHyprDirtyKey(stateKey) {
        let nextDirty = settingsPop.cloneMap(settingsPop.hyprDirtyValues);
        delete nextDirty[stateKey];
        settingsPop.hyprDirtyValues = nextDirty;

        let nextOrder = [];
        for (let i = 0; i < settingsPop.hyprDirtyOrder.length; i++) {
            if (settingsPop.hyprDirtyOrder[i] !== stateKey)
                nextOrder.push(settingsPop.hyprDirtyOrder[i]);
        }
        settingsPop.hyprDirtyOrder = nextOrder;
    }

    function hyprLabelForStateKey(stateKey) {
        for (let i = 0; i < settingsPop.hyprManagedOptions.length; i++) {
            let option = settingsPop.hyprManagedOptions[i];
            if (settingsPop.hyprStateKey(option) === stateKey)
                return settingsPop.hyprOptionMeta(option).label || stateKey;
        }

        return stateKey;
    }

    function hyprCommandValue(value) {
        return typeof value === "boolean" ? (value ? "true" : "false") : String(value);
    }

    function flushHyprStateWrites() {
        if (hyprApplyProc.running) {
            settingsPop.hyprApplyQueued = true;
            return;
        }

        settingsPop.runNextHyprStateWrite();
    }

    function runNextHyprStateWrite() {
        if (hyprApplyProc.running)
            return;

        for (let i = 0; i < settingsPop.hyprDirtyOrder.length; i++) {
            let stateKey = settingsPop.hyprDirtyOrder[i];
            let value = settingsPop.hyprDirtyValues[stateKey];
            let currentValue = settingsPop.themeState[stateKey];

            if (value === currentValue) {
                settingsPop.removeHyprDirtyKey(stateKey);
                i -= 1;
                continue;
            }

            hyprApplyProc.buf = "";
            hyprApplyProc.pendingStateKey = stateKey;
            hyprApplyProc.pendingValue = settingsPop.hyprCommandValue(value);
            hyprApplyProc.pendingLabel = settingsPop.hyprLabelForStateKey(stateKey);
            settingsPop.removeHyprDirtyKey(stateKey);
            hyprApplyProc.command = [
                "desktopctl",
                "theme",
                "set",
                stateKey,
                hyprApplyProc.pendingValue
            ];
            hyprApplyProc.running = true;
            return;
        }
    }

    function hyprIntValue(option) {
        let meta = settingsPop.hyprOptionMeta(option);
        let value = settingsPop.hyprStateValue(settingsPop.hyprStateKey(option), meta.fallback);
        let parsed = parseInt(value, 10);

        return isNaN(parsed) ? (meta.fallback === undefined ? 0 : meta.fallback) : parsed;
    }

    function hyprBoolValue(option) {
        let meta = settingsPop.hyprOptionMeta(option);
        let value = settingsPop.hyprStateValue(settingsPop.hyprStateKey(option), meta.fallback);
        return value === undefined ? !!meta.fallback : !!value;
    }

    function queueHyprOptionValue(option, value) {
        let stateKey = settingsPop.hyprStateKey(option);
        if (stateKey === "")
            return;

        let nextDraft = settingsPop.cloneMap(settingsPop.hyprDraftState);
        nextDraft[stateKey] = value;
        settingsPop.hyprDraftState = nextDraft;

        let nextDirty = settingsPop.cloneMap(settingsPop.hyprDirtyValues);
        nextDirty[stateKey] = value;
        settingsPop.hyprDirtyValues = nextDirty;

        if (settingsPop.hyprDirtyOrder.indexOf(stateKey) === -1) {
            let nextOrder = settingsPop.hyprDirtyOrder.slice(0);
            nextOrder.push(stateKey);
            settingsPop.hyprDirtyOrder = nextOrder;
        }

        hyprWriteTimer.restart();
    }

    function toggleHyprOption(option) {
        let nextValue = !settingsPop.hyprBoolValue(option);
        settingsPop.queueHyprOptionValue(option, nextValue);
    }

    function adjustHyprOption(option, direction) {
        let meta = settingsPop.hyprOptionMeta(option);
        let step = meta.step || 1;
        let nextValue = settingsPop.hyprIntValue(option) + direction * step;

        if (meta.minimum !== undefined && nextValue < meta.minimum)
            return;

        settingsPop.queueHyprOptionValue(option, nextValue);
    }

    function runSavePreset(name, presetData) {
        if (presetCommandProc.running)
            return;

        presetCommandError = "";
        presetCommandProc.buf = "";
        presetCommandProc.action = "save";
        presetCommandProc.targetName = name;
        presetCommandProc.command = [
            "desktopctl",
            "theme",
            "save-preset",
            name,
            JSON.stringify(presetData)
        ];
        presetCommandProc.running = true;
    }

    function runDeletePreset(name) {
        if (presetCommandProc.running)
            return;

        presetCommandError = "";
        presetCommandProc.buf = "";
        presetCommandProc.action = "delete";
        presetCommandProc.targetName = name;
        presetCommandProc.command = [
            "desktopctl",
            "theme",
            "delete-preset",
            name
        ];
        presetCommandProc.running = true;
    }

    // ── Apply commands ──
    Process {
        id: applyProc; running: false
        stderr: SplitParser { onRead: (line) => { console.log("[desktopctl theme stderr]", line); } }
        onExited: (code, status) => {
            if (code !== 0) {
                console.log("[desktopctl theme] exit", code);
                return;
            }

            settingsPop.loadThemeState();
        }
    }

    function runSet(key, value) {
        applyProc.command = ["desktopctl", "theme", "set", key, value];
        applyProc.running = true;
    }

    function runPreset(name) {
        applyProc.command = ["desktopctl", "theme", "preset", name];
        applyProc.running = true;
    }

    Process {
        id: presetCommandProc
        running: false
        property string buf: ""
        property string action: ""
        property string targetName: ""
        stdout: SplitParser { onRead: (line) => { presetCommandProc.buf += line; } }
        stderr: SplitParser { onRead: (line) => { presetCommandProc.buf += line; } }
        onExited: (code, status) => {
            let output = (buf || "").trim();

            if (code !== 0) {
                settingsPop.presetCommandError = output !== "" ? output : (
                    action === "delete" ? "Failed to delete preset" : "Failed to save preset"
                );
            } else {
                settingsPop.presetCommandError = "";
                settingsPop.presetMutationToken += 1;
                settingsPop.refreshPresets();
            }

            buf = "";
            action = "";
            targetName = "";
        }
    }

    // ── Backdrop ──
    Keys.onEscapePressed: settingsPop.close()

    // ── Animations ──
    SequentialAnimation {
        id: settingsOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: settingsContentLoader.item
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            Components.Anim {
                target: settingsContentLoader.item
                property: "scale"
                to: 1.0
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
        }
    }
    SequentialAnimation {
        id: settingsCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: settingsContentLoader.item
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: settingsContentLoader.item
                property: "scale"
                to: 0.92
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { settingsPop.closing = false; } }
    }

    Loader {
        id: settingsContentLoader
        width: 700
        height: 500
        anchors.centerIn: parent
        active: settingsPop.contentLoaded || settingsPop.active || settingsPop.closing
        asynchronous: true
        sourceComponent: settingsPanelComponent

        onLoaded: {
            item.opacity = 0;
            item.scale = 0.92;
            if (settingsPop.active)
                settingsOpenAnim.start();
        }
    }

    Component {
        id: settingsPanelComponent

        // ── Panel ──
        Rectangle {
            id: panel
            anchors.fill: parent
            radius: Theme.popupRadius
            color: Theme.bg
            border.width: 1
            border.color: Theme.bg3
            opacity: 0
            scale: 0.92
            transformOrigin: Item.Center
            clip: true
            layer.enabled: true

            Row {
                anchors.fill: parent

                Settings.SettingsSidebar {
                    selectedCategory: settingsPop.selectedCategory
                    categoryNames: settingsPop.categoryNames
                    categoryIcons: settingsPop.categoryIcons
                    systemCategoryCount: settingsPop.systemCategoryCount
                    onCategorySelected: (index) => settingsPop.selectedCategory = index
                }

                Rectangle {
                    width: 1
                    height: parent.height
                    color: Theme.bg3
                }

                Item {
                    width: parent.width - 191
                    height: parent.height

                    Loader {
                        id: detailLoader
                        anchors.fill: parent
                        anchors.margins: Theme.popupPadding
                        sourceComponent: {
                            switch (settingsPop.selectedCategory) {
                                case 0: return networkPane;
                                case 1: return bluetoothPane;
                                case 2: return audioPane;
                                case 3: return displayPane;
                                case 4: return powerPane;
                                case 5: return notificationsPane;
                                case 6: return focusTimePane;
                                case 7: return presetsPane;
                                case 8: return colorsPane;
                                case 9: return fontsPane;
                                case 10: return wallpaperPane;
                                case 11: return iconsPane;
                                case 12: return hyprlandPane;
                                default: return null;
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: networkPane
        Settings.SettingsNetworkPane {}
    }

    Component {
        id: bluetoothPane
        Settings.SettingsBluetoothPane {}
    }

    Component {
        id: audioPane
        Settings.SettingsAudioPane {}
    }

    Component {
        id: displayPane
        Settings.SettingsDisplayPane {}
    }

    Component {
        id: powerPane
        Settings.SettingsPowerPane {}
    }

    Component {
        id: notificationsPane
        Settings.SettingsNotificationsPane {}
    }

    Component {
        id: focusTimePane
        Settings.SettingsFocusTimePane {}
    }

    Component {
        id: presetsPane

        Settings.SettingsPresetsPane {
            presets: settingsPop.presets
            themeState: settingsPop.themeState
            colorFamilies: settingsPop.colorFamilies
            monoFontSizeOffsetTargets: settingsPop.monoFontSizeOffsetTargets
            presetCommandRunning: presetCommandProc.running
            presetCommandAction: presetCommandProc.action
            presetCommandTargetName: presetCommandProc.targetName
            presetCommandError: settingsPop.presetCommandError
            presetMutationToken: settingsPop.presetMutationToken
            onPresetActivated: (name) => settingsPop.runPreset(name)
            onPresetSaveRequested: (name, presetData) => settingsPop.runSavePreset(name, presetData)
            onPresetDeleteRequested: (name) => settingsPop.runDeletePreset(name)
        }
    }

    Component {
        id: colorsPane

        Settings.SettingsColorsPane {
            colorFamilies: settingsPop.colorFamilies
            themeState: settingsPop.themeState
            onColorSchemeSelected: (schemeName) => settingsPop.runSet("color_scheme", schemeName)
            onDarkHintSelected: (value) => settingsPop.runSet("dark_hint", value)
        }
    }

    Component {
        id: fontsPane

        Settings.SettingsFontsPane {
            themeState: settingsPop.themeState
            monoFontSizeOffsetTargets: settingsPop.monoFontSizeOffsetTargets
            onSetRequested: (key, value) => settingsPop.runSet(key, value)
        }
    }

    Component {
        id: wallpaperPane

        Settings.SettingsWallpaperPane {
            themeState: settingsPop.themeState
            wallpapers: settingsPop.wallpapers
            wallpaperDir: settingsPop.wallpaperDir
            directoryBrowserOpen: settingsPop.directoryBrowserOpen
            directoryBrowserPath: settingsPop.directoryBrowserPath
            directoryBrowserEntries: settingsPop.directoryBrowserEntries
            onSetRequested: (key, value) => settingsPop.runSet(key, value)
            onOpenDirectoryBrowserRequested: settingsPop.openDirectoryBrowser()
            onCloseDirectoryBrowserRequested: settingsPop.closeDirectoryBrowser()
            onBrowseDirectoryRequested: (name) => settingsPop.browseDirectory(name)
            onConfirmDirectoryBrowserRequested: settingsPop.confirmDirectoryBrowser()
        }
    }

    Component {
        id: hyprlandPane

        Settings.SettingsHyprlandPane {
            hyprRuntimeError: settingsPop.hyprRuntimeError
            hyprOptionInfo: settingsPop.hyprOptionInfo
            hyprGeneralOptions: settingsPop.hyprGeneralOptions
            hyprDecorationOptions: settingsPop.hyprDecorationOptions
            hyprBlurOptions: settingsPop.hyprBlurOptions
            hyprDraftState: settingsPop.hyprDraftState
            themeState: settingsPop.themeState
            onHyprOptionToggled: (option) => settingsPop.toggleHyprOption(option)
            onHyprOptionAdjusted: (option, direction) => settingsPop.adjustHyprOption(option, direction)
        }
    }

    Component {
        id: iconsPane

        Settings.SettingsIconsPane {
            themeState: settingsPop.themeState
            onSetRequested: (key, value) => settingsPop.runSet(key, value)
        }
    }
}
