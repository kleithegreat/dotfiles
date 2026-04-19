import qs
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

    // ── State ──
    property var themeState: ({})
    property var colorSchemes: []
    property var colorFamilies: []
    property var presets: []
    property var wallpapers: []
    property var wallpaperPreviewPaths: ({})
    property bool directoryBrowserOpen: false
    property string directoryBrowserPath: "/home/kevin/repos/dotfiles/wallpapers"
    property var directoryBrowserEntries: []
    property var fontSizeOffsetTargets: [
        { label: "Quickshell", key: "quickshell_font_size_offset" },
        { label: "GTK", key: "gtk_font_size_offset" },
        { label: "Qt", key: "qt_font_size_offset" }
    ]
    property var monoFontSizeOffsetTargets: [
        { label: "Alacritty", key: "alacritty_mono_font_size_offset" },
        { label: "Ghostty", key: "ghostty_mono_font_size_offset" },
        { label: "GTK", key: "gtk_mono_font_size_offset" },
        { label: "Neovide", key: "neovide_mono_font_size_offset" },
        { label: "Qt", key: "qt_mono_font_size_offset" },
        { label: "VS Code", key: "vscode_mono_font_size_offset" }
    ]
    property int selectedCategory: 0
    property int systemCategoryCount: 8
    property var hiddenCategories: {
        var h = [];
        if (!HostCapabilities.hasBattery && !HostCapabilities.hasPowerProfiles) h.push(4);
        if (!HostCapabilities.isLaptop || !HostCapabilities.hasFingerprintReader) h.push(5);
        return h;
    }
    property string wallpaperDir: "/home/kevin/repos/dotfiles/wallpapers"
    property var categoryNames: ["Network", "Bluetooth", "Audio", "Display", "Power", "Fingerprint", "Notifications", "Screen Time", "Presets", "Colors", "Fonts", "Wallpaper", "Icons", "Mouse", "Hyprland"]
    property var categoryIcons: ["../icons/wifi.svg", "../icons/bluetooth-on.svg", "../icons/volume-high.svg", "../icons/monitor.svg", "../icons/bolt.svg", "../icons/shield-lock.svg", "../icons/bell.svg", "../icons/hourglass.svg", "../icons/adjustments.svg", "../icons/palette.svg", "../icons/typography.svg", "../icons/photo.svg", "../icons/certificate.svg", "../icons/cursor.svg", "../icons/layout.svg"]
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
    property var themeWriteQueue: []
    property bool themeWriteDrainAfterReload: false
    readonly property bool themeWritePending: applyProc.running && applyProc.mode === "set" && applyProc.pendingKey !== ""
    readonly property string pendingThemeKey: applyProc.pendingKey
    property var mouseSettings: ({})
    property string mouseRuntimeError: ""
    property bool mouseStateReloadPending: false
    property var mouseWriteQueue: []
    property bool mouseWriteDrainAfterReload: false
    readonly property bool mouseWritePending: mouseApplyProc.running && mouseApplyProc.pendingKey !== ""
    readonly property string pendingMouseKey: mouseApplyProc.pendingKey
    property string fingerprintDeviceName: ""
    property string fingerprintDevicePath: ""
    property var fingerprintEnrolledFingers: []
    property string fingerprintRuntimeError: ""
    property bool fingerprintStateReloadPending: false
    property bool fingerprintMetadataReloadPending: false
    property string fingerprintActionMode: ""
    property string fingerprintActionFinger: ""
    property string fingerprintActionStatus: ""
    property string fingerprintActionError: ""
    property string fingerprintActionTone: ""
    property bool fingerprintCancelRequested: false
    property int fingerprintEnrollStagesCompleted: 0
    property int fingerprintEnrollStagesTotal: 0
    property string fingerprintEnrollScanType: "press"
    readonly property bool fingerprintStateLoading: fingerprintListProc.running
    readonly property bool fingerprintActionBusy: fingerprintEnrollProc.running || fingerprintDeleteProc.running
    readonly property int panelWidth: {
        let available = Math.max(420, settingsPop.width - Theme.gapOut * 4);
        let preferred = Math.round((Theme.fontSize + Theme.popupPadding) * 28);
        let minimum = Math.round((Theme.fontSize + Theme.popupPadding) * 22);
        return Math.max(Math.min(available, preferred), Math.min(available, minimum));
    }
    readonly property int panelHeight: {
        let available = Math.max(320, settingsPop.height - Theme.popupTopMargin - Theme.gapOut * 2);
        let preferred = Math.round((Theme.fontSize + Theme.popupPadding) * 19);
        let minimum = Math.round((Theme.fontSize + Theme.popupPadding) * 16);
        return Math.max(Math.min(available, preferred), Math.min(available, minimum));
    }

    function preparePanelForOpen() {
        let item = settingsContentLoader.item;
        if (!item)
            return false;

        item.opacity = 0;
        item.scale = Theme.popupStartScale;
        return true;
    }

    onActiveChanged: {
        if (active) {
            forceActiveFocus();
            contentLoaded = true;
            loadState();
            settingsRefreshTimer.stop();
            settingsRefreshTimer.start();
            if (preparePanelForOpen())
                settingsOpenAnim.start();
        }
        else if (!closing) {
            settingsRefreshTimer.stop();
            cancelFingerprintAction();
            closeDirectoryBrowser();
            if (settingsContentLoader.item) {
                closing = true;
                settingsCloseAnim.start();
            } else {
                closing = false;
            }
        }
    }

    Timer {
        id: settingsRefreshTimer
        interval: Theme.animPopupIn
        repeat: false
        onTriggered: {
            if (settingsPop.active)
                settingsPop.refreshSystemServices();
        }
    }

    // Warm the heavy popup shell in the background so the first open can animate
    // the real panel instead of showing the placeholder shell first.
    Timer {
        interval: 2500
        running: !settingsPop.contentLoaded
        repeat: false
        onTriggered: settingsPop.contentLoaded = true
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
        HyprlandConfigService.refresh();
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

    function loadMouseSettings() {
        if (mouseStateProc.running) {
            mouseStateReloadPending = true;
            return;
        }

        mouseStateReloadPending = false;
        mouseStateProc.buf = "";
        mouseStateProc.errorBuf = "";
        mouseStateProc.running = true;
    }

    function loadState() {
        loadThemeState();
        loadMouseSettings();
        loadFingerprintState();
        refreshColorFamilies();
        refreshPresets();
        refreshWallpapers();
    }

    function fingerprintDisplayName(finger) {
        if (!finger || finger === "")
            return "Fingerprint";

        let parts = String(finger).split("-");
        let words = [];
        for (let i = 0; i < parts.length; i++) {
            let part = parts[i];
            words.push(part.charAt(0).toUpperCase() + part.slice(1));
        }

        return words.join(" ");
    }

    function fingerprintScanVerb(capitalized) {
        let word = fingerprintEnrollScanType === "swipe" ? "swipe" : "touch";
        return capitalized ? word.charAt(0).toUpperCase() + word.slice(1) : word;
    }

    function resetFingerprintEnrollmentProgress() {
        fingerprintEnrollStagesCompleted = 0;
        fingerprintActionTone = "";
    }

    function loadFingerprintDeviceMetadata() {
        if (!HostCapabilities.isLaptop || !HostCapabilities.hasFingerprintReader) {
            fingerprintDevicePath = "";
            fingerprintEnrollStagesTotal = 0;
            fingerprintEnrollScanType = "press";
            return;
        }

        if (fingerprintMetadataProc.running) {
            fingerprintMetadataReloadPending = true;
            return;
        }

        fingerprintMetadataReloadPending = false;
        fingerprintMetadataProc.errorBuf = "";
        fingerprintMetadataProc.running = true;
    }

    function applyFingerprintMetadataLine(line) {
        let trimmed = String(line || "").trim();
        if (trimmed === "")
            return;

        if (trimmed.indexOf("path=") === 0) {
            fingerprintDevicePath = trimmed.slice(5);
            return;
        }

        if (trimmed.indexOf("i ") === 0) {
            let parsedStages = Number(trimmed.slice(2).trim());
            if (!isNaN(parsedStages) && parsedStages > 0)
                fingerprintEnrollStagesTotal = parsedStages;
            return;
        }

        if (trimmed.indexOf("s ") === 0) {
            let scanType = trimmed.slice(2).trim();
            if (scanType.charAt(0) === '"' && scanType.charAt(scanType.length - 1) === '"')
                scanType = scanType.slice(1, scanType.length - 1);
            if (scanType !== "")
                fingerprintEnrollScanType = scanType;
        }
    }

    function fingerprintRetryMessage(result) {
        switch (result) {
        case "enroll-remove-and-retry":
            return fingerprintScanVerb(true) + " the sensor again after lifting your finger.";
        case "enroll-swipe-too-short":
            return "Swipe a little farther across the sensor.";
        case "enroll-finger-not-centered":
            return "Center your finger on the sensor and try again.";
        case "enroll-too-fast":
            return fingerprintEnrollScanType === "swipe"
                ? "Swipe a little more slowly across the sensor."
                : "Hold your finger a little longer on the sensor.";
        case "enroll-retry-scan":
            return fingerprintScanVerb(true) + " the sensor again from a slightly different angle.";
        case "enroll-duplicate":
            return "That fingerprint is already enrolled.";
        case "enroll-data-full":
            return "No more fingerprints can be stored on this reader.";
        case "enroll-disconnected":
            return "The fingerprint reader disconnected during enrollment.";
        case "enroll-failed":
            return "Fingerprint enrollment failed. Try again.";
        case "enroll-unknown-error":
            return "Fingerprint enrollment hit an unexpected error.";
        default:
            return fingerprintScanVerb(true) + " the sensor again to continue.";
        }
    }

    function applyFingerprintEnrollSignal(result, done) {
        if (result === "enroll-stage-passed") {
            if (fingerprintEnrollStagesTotal > 0)
                fingerprintEnrollStagesCompleted = Math.min(fingerprintEnrollStagesCompleted + 1, fingerprintEnrollStagesTotal);

            fingerprintActionTone = "progress";
            if (done || (fingerprintEnrollStagesTotal > 0 && fingerprintEnrollStagesCompleted >= fingerprintEnrollStagesTotal))
                fingerprintActionStatus = "Final capture recorded. Saving your fingerprint...";
            else if (fingerprintEnrollScanType === "swipe")
                fingerprintActionStatus = "Good swipe. Swipe again to capture another part of your fingerprint.";
            else
                fingerprintActionStatus = "Good scan. Lift your finger, then touch the sensor again.";

            return;
        }

        if (result === "enroll-completed") {
            if (fingerprintEnrollStagesTotal > 0)
                fingerprintEnrollStagesCompleted = fingerprintEnrollStagesTotal;
            fingerprintActionTone = "progress";
            fingerprintActionStatus = "Fingerprint captured. Saving it now...";
            return;
        }

        fingerprintActionTone = "retry";
        fingerprintActionStatus = fingerprintRetryMessage(result);
    }

    function handleFingerprintEnrollOutputLine(line) {
        let trimmed = String(line || "").trim();
        if (trimmed === "")
            return;

        if (trimmed.indexOf("Using device ") === 0)
            return;

        if (trimmed.indexOf("Enrolling ") === 0) {
            fingerprintActionTone = "progress";
            fingerprintActionStatus = "Ready. " + fingerprintScanVerb(true) + " the sensor to start capturing your fingerprint.";
            return;
        }

        let resultMatch = trimmed.match(/\b(enroll-(?:stage-passed|completed|failed|swipe-too-short|finger-not-centered|remove-and-retry|too-fast|retry-scan|disconnected|unknown-error|duplicate|data-full))\b/);
        if (resultMatch) {
            applyFingerprintEnrollSignal(resultMatch[1], resultMatch[1] === "enroll-completed");
            return;
        }

        if (trimmed.indexOf("Place your ") === 0 || trimmed.indexOf("Swipe your ") === 0) {
            fingerprintActionTone = "progress";
            fingerprintActionStatus = trimmed;
        }
    }

    function loadFingerprintState() {
        if (!HostCapabilities.isLaptop || !HostCapabilities.hasFingerprintReader) {
            fingerprintDeviceName = "";
            fingerprintDevicePath = "";
            fingerprintEnrolledFingers = [];
            fingerprintRuntimeError = "";
            fingerprintEnrollStagesTotal = 0;
            fingerprintEnrollScanType = "press";
            resetFingerprintEnrollmentProgress();
            return;
        }

        loadFingerprintDeviceMetadata();

        if (fingerprintListProc.running) {
            fingerprintStateReloadPending = true;
            return;
        }

        fingerprintStateReloadPending = false;
        fingerprintListProc.buf = "";
        fingerprintListProc.errorBuf = "";
        fingerprintListProc.running = true;
    }

    function parseFingerprintState(output) {
        let nextDeviceName = "";
        let nextFingers = [];
        let lines = String(output || "").split("\n");

        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim();
            if (line === "")
                continue;

            if (line.indexOf("Fingerprints for user ") === 0) {
                let onIndex = line.indexOf(" on ");
                let colonIndex = line.lastIndexOf(":");
                if (onIndex >= 0 && colonIndex > onIndex)
                    nextDeviceName = line.slice(onIndex + 4, colonIndex).trim();
                continue;
            }

            if (line.indexOf("- #") === 0) {
                let colon = line.indexOf(":");
                let finger = colon >= 0 ? line.slice(colon + 1).trim() : "";
                if (finger !== "" && nextFingers.indexOf(finger) === -1)
                    nextFingers.push(finger);
            }
        }

        fingerprintDeviceName = nextDeviceName;
        fingerprintEnrolledFingers = nextFingers;
    }

    function startFingerprintEnroll(finger) {
        if (!finger || finger === "" || fingerprintActionBusy)
            return;

        loadFingerprintDeviceMetadata();
        resetFingerprintEnrollmentProgress();
        fingerprintActionMode = "enroll";
        fingerprintActionFinger = finger;
        fingerprintActionTone = "progress";
        fingerprintActionStatus = fingerprintScanVerb(true) + " the sensor repeatedly to enroll " + fingerprintDisplayName(finger) + ".";
        fingerprintActionError = "";
        fingerprintCancelRequested = false;
        fingerprintEnrollProc.buf = "";
        fingerprintEnrollProc.errorBuf = "";
        fingerprintEnrollProc.command = ["bash", "-lc", "exec stdbuf -oL -eL fprintd-enroll \"$(id -un)\" -f \"$1\"", "_", finger];
        fingerprintEnrollProc.running = true;
    }

    function startFingerprintDelete(finger) {
        if (!finger || finger === "" || fingerprintActionBusy)
            return;

        resetFingerprintEnrollmentProgress();
        fingerprintActionMode = "delete";
        fingerprintActionFinger = finger;
        fingerprintActionStatus = "Removing " + fingerprintDisplayName(finger) + ".";
        fingerprintActionError = "";
        fingerprintActionTone = "";
        fingerprintCancelRequested = false;
        fingerprintDeleteProc.buf = "";
        fingerprintDeleteProc.errorBuf = "";
        fingerprintDeleteProc.command = ["bash", "-lc", "fprintd-delete \"$(id -un)\" -f \"$1\"", "_", finger];
        fingerprintDeleteProc.running = true;
    }

    function cancelFingerprintAction() {
        if (!fingerprintEnrollProc.running)
            return;

        fingerprintCancelRequested = true;
        fingerprintEnrollProc.running = false;
    }

    function cloneThemeState(source) {
        return JSON.parse(JSON.stringify(source || ({})));
    }

    function coerceThemeValue(key, value) {
        if (key === "dark_hint") {
            if (value === "light" || value === false || value === "false" || value === "off")
                return false;
            return true;
        }

        let current = themeState[key];
        if (typeof current === "boolean")
            return value === true || value === "true" || value === "on";
        if (typeof current === "number") {
            let parsed = Number(value);
            return isNaN(parsed) ? current : parsed;
        }
        return value;
    }

    function stageThemeValue(key, value) {
        let nextState = cloneThemeState(themeState);
        nextState[key] = coerceThemeValue(key, value);
        themeState = nextState;
    }

    function coerceMouseValue(key, value) {
        if (key === "accel_profile")
            return String(value);

        let parsed = Number(value);
        return isNaN(parsed) ? value : parsed;
    }

    function stageMouseValue(key, value) {
        let nextState = cloneMap(mouseSettings);
        nextState[key] = coerceMouseValue(key, value);
        mouseSettings = nextState;
    }

    function isThemeKeyPending(key) {
        return themeWritePending && pendingThemeKey === key;
    }

    Process {
        id: stateProc; command: ["desktopctl", "theme", "status", "--json"]; running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { stateProc.buf += line; } }
        onExited: (code) => {
            let parsed = false;
            let trimmed = buf.trim();
            try {
                if (code === 0 && trimmed !== "") {
                    settingsPop.themeState = JSON.parse(buf);
                    settingsPop.syncHyprDraftState();
                    parsed = true;
                }
            } catch(e) {
                ToastService.showError("Failed to parse theme state");
            }

            if (code !== 0)
                ToastService.showError("Failed to load theme state");
            else if (!parsed && trimmed === "")
                ToastService.showError("Theme state is empty");

            buf = "";

            if (settingsPop.themeStateReloadPending) {
                settingsPop.loadThemeState();
                return;
            }

            if (settingsPop.themeWriteDrainAfterReload) {
                settingsPop.themeWriteDrainAfterReload = false;
                settingsPop.startNextThemeWrite();
                return;
            }

            settingsPop.startNextThemeWrite();
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
                    appearance: d.appearance || (String(d.variant || "").toLowerCase().indexOf("light") >= 0 ? "light" : "dark"),
                    bg: d.bg || "#282828",
                    bg_dim: d.bg_dim || d.bg || "#1d2021",
                    bg1: d.bg1 || d.bg || "#3c3836",
                    bg2: d.bg2 || d.bg1 || d.bg || "#504945",
                    bg3: d.bg3 || d.bg2 || d.bg1 || d.bg || "#665c54",
                    fg: d.fg || "#ebdbb2",
                    fg2: d.fg2 || d.fg || "#d5c4a1",
                    fg3: d.fg3 || d.fg2 || d.fg || "#bdae93",
                    fg4: d.fg4 || d.fg3 || d.fg2 || d.fg || "#a89984",
                    accent: d.accent || d.blue || "#458588",
                    red: d.red || "#cc241d",
                    orange: d.orange || d.yellow || "#d65d0e",
                    green: d.green || "#98971a",
                    blue: d.blue || "#458588",
                    yellow: d.yellow || "#d79921",
                    purple: d.purple || "#b16286",
                    cyan: d.cyan || d.blue || "#689d6a",
                    palette: Array.isArray(d.palette) ? d.palette : []
                });
            }
            settingsPop.colorSchemes = schemes;
            settingsPop.colorFamilies = result;
            buf = "";
        }
    }

    Process {
        id: mouseStateProc
        command: ["desktopctl", "hypr", "input", "status", "--json"]
        running: false
        property string buf: ""
        property string errorBuf: ""
        stdout: SplitParser { onRead: (line) => { mouseStateProc.buf += line; } }
        stderr: SplitParser { onRead: (line) => { mouseStateProc.errorBuf += line + "\n"; } }
        onExited: (code) => {
            let parsed = false;
            let trimmed = buf.trim();
            let errorMessage = errorBuf.trim();

            try {
                if (code === 0 && trimmed !== "") {
                    settingsPop.mouseSettings = JSON.parse(trimmed);
                    settingsPop.mouseRuntimeError = "";
                    parsed = true;
                }
            } catch (e) {
                settingsPop.mouseRuntimeError = "Failed to parse mouse settings";
                ToastService.showError(settingsPop.mouseRuntimeError);
            }

            if (code !== 0) {
                settingsPop.mouseRuntimeError = errorMessage !== "" ? errorMessage : "Failed to load mouse settings";
                ToastService.showError(settingsPop.mouseRuntimeError);
            } else if (!parsed && trimmed === "") {
                settingsPop.mouseRuntimeError = "Mouse settings are empty";
                ToastService.showError(settingsPop.mouseRuntimeError);
            }

            buf = "";
            errorBuf = "";

            if (settingsPop.mouseStateReloadPending) {
                settingsPop.loadMouseSettings();
                return;
            }

            if (settingsPop.mouseWriteDrainAfterReload) {
                settingsPop.mouseWriteDrainAfterReload = false;
                settingsPop.startNextMouseWrite();
                return;
            }

            settingsPop.startNextMouseWrite();
        }
    }

    Process {
        id: fingerprintMetadataProc
        command: [
            "bash",
            "-lc",
            "path=$(busctl call net.reactivated.Fprint /net/reactivated/Fprint/Manager net.reactivated.Fprint.Manager GetDefaultDevice); path=${path#*\\\"}; path=${path%%\\\"*}; printf 'path=%s\\n' \"$path\"; busctl get-property net.reactivated.Fprint \"$path\" net.reactivated.Fprint.Device num-enroll-stages; busctl get-property net.reactivated.Fprint \"$path\" net.reactivated.Fprint.Device scan-type"
        ]
        running: false
        property string errorBuf: ""
        stdout: SplitParser { onRead: (line) => settingsPop.applyFingerprintMetadataLine(line) }
        stderr: SplitParser { onRead: (line) => { fingerprintMetadataProc.errorBuf += line + "\n"; } }
        onExited: (code) => {
            if (code !== 0) {
                settingsPop.fingerprintDevicePath = settingsPop.fingerprintDevicePath || "/net/reactivated/Fprint/Device/0";
                settingsPop.fingerprintEnrollScanType = settingsPop.fingerprintEnrollScanType || "press";
            }

            errorBuf = "";

            if (settingsPop.fingerprintMetadataReloadPending)
                settingsPop.loadFingerprintDeviceMetadata();
        }
    }

    Process {
        id: fingerprintListProc
        command: ["bash", "-lc", "fprintd-list \"$(id -un)\""]
        running: false
        property string buf: ""
        property string errorBuf: ""
        stdout: SplitParser { onRead: (line) => { fingerprintListProc.buf += line + "\n"; } }
        stderr: SplitParser { onRead: (line) => { fingerprintListProc.errorBuf += line + "\n"; } }
        onExited: (code) => {
            let output = (buf + errorBuf).trim();
            if (code === 0) {
                settingsPop.parseFingerprintState(buf);
                settingsPop.fingerprintRuntimeError = "";
            } else {
                settingsPop.fingerprintDeviceName = "";
                settingsPop.fingerprintEnrolledFingers = [];
                settingsPop.fingerprintRuntimeError = output !== "" ? output : "Failed to load fingerprint status";
            }

            buf = "";
            errorBuf = "";

            if (settingsPop.fingerprintStateReloadPending)
                settingsPop.loadFingerprintState();
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
        command: ["desktopctl", "theme", "list-wallpapers", "--json", "--directory", settingsPop.wallpaperDir]
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { listWallpapersProc.buf += line; } }
        onExited: {
            let items = [];
            let previewPaths = {};
            try {
                let parsed = JSON.parse(buf);
                if (Array.isArray(parsed)) {
                    for (let i = 0; i < parsed.length; i++) {
                        let entry = parsed[i] || {};
                        let name = String(entry.name || "").trim();
                        if (name === "")
                            continue;
                        items.push(name);
                        if (entry.preview_path)
                            previewPaths[name] = String(entry.preview_path);
                    }
                }
            } catch (e) {}
            settingsPop.wallpapers = items;
            settingsPop.wallpaperPreviewPaths = previewPaths;
            buf = "";
        }
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

    function queueThemeWrite(request) {
        let nextQueue = themeWriteQueue.slice(0);
        nextQueue.push(request);
        themeWriteQueue = nextQueue;
        startNextThemeWrite();
    }

    function startNextThemeWrite() {
        if (applyProc.running || stateProc.running || themeWriteDrainAfterReload || themeWriteQueue.length === 0)
            return;

        let nextQueue = themeWriteQueue.slice(0);
        let request = nextQueue.shift();
        themeWriteQueue = nextQueue;

        applyProc.mode = request.mode;
        applyProc.pendingKey = request.key || "";
        applyProc.rollbackState = request.mode === "set" ? cloneThemeState(themeState) : ({});
        applyProc.errorBuf = "";
        if (request.mode === "set")
            stageThemeValue(request.key, request.value);
        applyProc.command = request.command;
        applyProc.running = true;
    }

    function queueMouseWrite(request) {
        let nextQueue = mouseWriteQueue.slice(0);
        nextQueue.push(request);
        mouseWriteQueue = nextQueue;
        startNextMouseWrite();
    }

    function startNextMouseWrite() {
        if (mouseApplyProc.running || mouseStateProc.running || mouseWriteDrainAfterReload || mouseWriteQueue.length === 0)
            return;

        let nextQueue = mouseWriteQueue.slice(0);
        let request = nextQueue.shift();
        mouseWriteQueue = nextQueue;

        mouseApplyProc.pendingKey = request.key;
        mouseApplyProc.rollbackState = cloneMap(mouseSettings);
        mouseApplyProc.errorBuf = "";
        stageMouseValue(request.key, request.value);
        mouseApplyProc.command = request.command;
        mouseApplyProc.running = true;
    }

    // ── Apply commands ──
    Process {
        id: applyProc; running: false
        property string mode: ""
        property string pendingKey: ""
        property var rollbackState: ({})
        property string errorBuf: ""
        stderr: SplitParser {
            onRead: (line) => {
                applyProc.errorBuf += line + "\n";
                console.log("[desktopctl theme stderr]", line);
            }
        }
        onExited: (code, status) => {
            let errorMessage = applyProc.errorBuf.trim();
            if (code !== 0) {
                if (mode === "set")
                    settingsPop.themeState = rollbackState;
                ToastService.showError(errorMessage !== "" ? errorMessage : "Theme command failed");
            } else {
                settingsPop.themeWriteDrainAfterReload = true;
                settingsPop.loadThemeState();
            }

            mode = "";
            pendingKey = "";
            rollbackState = ({});
            errorBuf = "";

            if (code !== 0)
                settingsPop.startNextThemeWrite();
        }
    }

    function runSet(key, value) {
        let commandValue = String(value);
        queueThemeWrite({
            mode: "set",
            key: key,
            value: value,
            command: ["desktopctl", "theme", "set", key, commandValue]
        });
    }

    function runMouseSet(key, value) {
        let commandValue = String(value);
        queueMouseWrite({
            key: key,
            value: value,
            command: ["desktopctl", "hypr", "input", "set", key, commandValue]
        });
    }

    function runPreset(name) {
        queueThemeWrite({
            mode: "preset",
            key: "",
            command: ["desktopctl", "theme", "preset", name]
        });
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

    Process {
        id: mouseApplyProc
        running: false
        property string pendingKey: ""
        property var rollbackState: ({})
        property string errorBuf: ""
        stderr: SplitParser {
            onRead: (line) => {
                mouseApplyProc.errorBuf += line + "\n";
                console.log("[desktopctl hypr stderr]", line);
            }
        }
        onExited: (code) => {
            let errorMessage = mouseApplyProc.errorBuf.trim();
            if (code !== 0) {
                settingsPop.mouseSettings = mouseApplyProc.rollbackState;
                settingsPop.mouseRuntimeError = errorMessage !== "" ? errorMessage : "Mouse command failed";
                ToastService.showError(settingsPop.mouseRuntimeError);
            } else {
                settingsPop.mouseRuntimeError = "";
                settingsPop.mouseWriteDrainAfterReload = true;
                settingsPop.loadMouseSettings();
            }

            pendingKey = "";
            rollbackState = ({});
            errorBuf = "";

            if (code !== 0)
                settingsPop.startNextMouseWrite();
        }
    }

    Process {
        id: fingerprintEnrollProc
        running: false
        property string buf: ""
        property string errorBuf: ""
        stdout: SplitParser { onRead: (line) => {
            fingerprintEnrollProc.buf += line + "\n";
            settingsPop.handleFingerprintEnrollOutputLine(line);
        } }
        stderr: SplitParser { onRead: (line) => {
            fingerprintEnrollProc.errorBuf += line + "\n";
            settingsPop.handleFingerprintEnrollOutputLine(line);
        } }
        onExited: (code) => {
            let displayName = settingsPop.fingerprintDisplayName(settingsPop.fingerprintActionFinger);
            let output = (buf + errorBuf).trim();

            if (settingsPop.fingerprintCancelRequested) {
                settingsPop.fingerprintActionError = "";
                settingsPop.fingerprintActionTone = "";
                settingsPop.fingerprintActionStatus = "Canceled fingerprint enrollment.";
            } else if (code !== 0) {
                settingsPop.fingerprintActionTone = "";
                settingsPop.fingerprintActionError = output !== "" ? output : "Failed to enroll " + displayName + ".";
                settingsPop.fingerprintActionStatus = "";
            } else {
                if (settingsPop.fingerprintEnrollStagesTotal > 0)
                    settingsPop.fingerprintEnrollStagesCompleted = settingsPop.fingerprintEnrollStagesTotal;
                settingsPop.fingerprintActionTone = "";
                settingsPop.fingerprintActionError = "";
                settingsPop.fingerprintActionStatus = "Saved " + displayName + ".";
            }

            settingsPop.fingerprintActionMode = "";
            settingsPop.fingerprintActionFinger = "";
            settingsPop.fingerprintCancelRequested = false;
            buf = "";
            errorBuf = "";
            settingsPop.loadFingerprintState();
        }
    }

    Process {
        id: fingerprintDeleteProc
        running: false
        property string buf: ""
        property string errorBuf: ""
        stdout: SplitParser { onRead: (line) => { fingerprintDeleteProc.buf += line + "\n"; } }
        stderr: SplitParser { onRead: (line) => { fingerprintDeleteProc.errorBuf += line + "\n"; } }
        onExited: (code) => {
            let displayName = settingsPop.fingerprintDisplayName(settingsPop.fingerprintActionFinger);
            let output = (buf + errorBuf).trim();

            if (code !== 0) {
                settingsPop.fingerprintActionTone = "";
                settingsPop.fingerprintActionError = output !== "" ? output : "Failed to remove " + displayName + ".";
                settingsPop.fingerprintActionStatus = "";
            } else {
                settingsPop.fingerprintActionTone = "";
                settingsPop.fingerprintActionError = "";
                settingsPop.fingerprintActionStatus = "Removed " + displayName + ".";
            }

            settingsPop.fingerprintActionMode = "";
            settingsPop.fingerprintActionFinger = "";
            settingsPop.fingerprintCancelRequested = false;
            buf = "";
            errorBuf = "";
            settingsPop.loadFingerprintState();
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
            SequentialAnimation {
                PauseAnimation { duration: Theme.animPopupScaleLead }
                Components.Anim {
                    target: settingsContentLoader.item
                    property: "scale"
                    to: 1.0
                    duration: Math.max(0, Theme.animPopupIn - Theme.animPopupScaleLead)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveEmphasizedEnter
                }
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
                to: Theme.popupStartScale
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { settingsPop.closing = false; } }
    }

    Rectangle {
        anchors.centerIn: parent
        width: settingsContentLoader.width
        height: settingsContentLoader.height
        visible: settingsPop.overlayVisible && !settingsPop.closing && !settingsContentLoader.item
        opacity: 1
        radius: Theme.popupRadius
        color: Theme.bg
        border.width: 1
        border.color: Theme.bg3

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Loader {
        id: settingsContentLoader
        width: settingsPop.panelWidth
        height: settingsPop.panelHeight
        anchors.centerIn: parent
        active: settingsPop.contentLoaded || settingsPop.active || settingsPop.closing
        asynchronous: true
        sourceComponent: settingsPanelComponent

        onLoaded: {
            item.opacity = 0;
            item.scale = Theme.popupStartScale;
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
            scale: Theme.popupStartScale
            transformOrigin: Item.Center
            clip: true
            layer.enabled: settingsOpenAnim.running || settingsCloseAnim.running
            layer.smooth: true

            Row {
                anchors.fill: parent

                Settings.SettingsSidebar {
                    id: sidebarPanel
                    selectedCategory: settingsPop.selectedCategory
                    categoryNames: settingsPop.categoryNames
                    categoryIcons: settingsPop.categoryIcons
                    systemCategoryCount: settingsPop.systemCategoryCount
                    hiddenCategories: settingsPop.hiddenCategories
                    onCategorySelected: (index) => settingsPop.selectedCategory = index
                }

                Rectangle {
                    width: 1
                    height: parent.height
                    color: Theme.bg3
                }

                Item {
                    id: paneContainer
                    width: parent.width - sidebarPanel.width - 1
                    height: parent.height

                    property int _activePane: settingsPop.selectedCategory

                    Connections {
                        target: settingsPop
                        function onSelectedCategoryChanged() {
                            if (detailLoader.item) {
                                paneSwapAnim.stop();
                                paneSwapAnim.start();
                            } else {
                                paneContainer._activePane = settingsPop.selectedCategory;
                            }
                        }
                    }

                    SequentialAnimation {
                        id: paneSwapAnim
                        Components.Anim {
                            target: detailLoader; property: "opacity"; to: 0
                            duration: Math.round(Theme.animContentSwap / 2)
                            easing.type: Easing.InQuad
                        }
                        ScriptAction {
                            script: { paneContainer._activePane = settingsPop.selectedCategory; }
                        }
                        Components.Anim {
                            target: detailLoader; property: "opacity"; to: 1
                            duration: Math.round(Theme.animContentSwap / 2)
                            easing.type: Easing.OutCubic
                        }
                    }

                    Loader {
                        id: detailLoader
                        anchors.fill: parent
                        anchors.margins: Theme.popupPadding
                        sourceComponent: {
                            switch (paneContainer._activePane) {
                                case 0: return networkPane;
                                case 1: return bluetoothPane;
                                case 2: return audioPane;
                                case 3: return displayPane;
                                case 4: return powerPane;
                                case 5: return fingerprintPane;
                                case 6: return notificationsPane;
                                case 7: return focusTimePane;
                                case 8: return presetsPane;
                                case 9: return colorsPane;
                                case 10: return fontsPane;
                                case 11: return wallpaperPane;
                                case 12: return iconsPane;
                                case 13: return mousePane;
                                case 14: return hyprlandPane;
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
        id: fingerprintPane

        Settings.SettingsFingerprintPane {
            stateLoading: settingsPop.fingerprintStateLoading
            deviceName: settingsPop.fingerprintDeviceName
            enrolledFingers: settingsPop.fingerprintEnrolledFingers
            runtimeError: settingsPop.fingerprintRuntimeError
            actionBusy: settingsPop.fingerprintActionBusy
            actionMode: settingsPop.fingerprintActionMode
            actionFinger: settingsPop.fingerprintActionFinger
            actionStatus: settingsPop.fingerprintActionStatus
            actionError: settingsPop.fingerprintActionError
            actionTone: settingsPop.fingerprintActionTone
            enrollStagesCompleted: settingsPop.fingerprintEnrollStagesCompleted
            enrollStagesTotal: settingsPop.fingerprintEnrollStagesTotal
            enrollScanType: settingsPop.fingerprintEnrollScanType
            onRefreshRequested: settingsPop.loadFingerprintState()
            onEnrollRequested: (finger) => settingsPop.startFingerprintEnroll(finger)
            onDeleteRequested: (finger) => settingsPop.startFingerprintDelete(finger)
            onCancelRequested: settingsPop.cancelFingerprintAction()
        }
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
            wallpapers: settingsPop.wallpapers
            wallpaperDir: settingsPop.wallpaperDir
            fontSizeOffsetTargets: settingsPop.fontSizeOffsetTargets
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
            writePending: settingsPop.themeWritePending
            pendingKey: settingsPop.pendingThemeKey
            onColorSchemeSelected: (schemeName) => settingsPop.runSet("color_scheme", schemeName)
            onDarkHintSelected: (value) => settingsPop.runSet("dark_hint", value)
        }
    }

    Component {
        id: fontsPane

        Settings.SettingsFontsPane {
            themeState: settingsPop.themeState
            writePending: settingsPop.themeWritePending
            pendingKey: settingsPop.pendingThemeKey
            fontSizeOffsetTargets: settingsPop.fontSizeOffsetTargets
            monoFontSizeOffsetTargets: settingsPop.monoFontSizeOffsetTargets
            onSetRequested: (key, value) => settingsPop.runSet(key, value)
        }
    }

    Component {
        id: wallpaperPane

        Settings.SettingsWallpaperPane {
            themeState: settingsPop.themeState
            writePending: settingsPop.themeWritePending
            pendingKey: settingsPop.pendingThemeKey
            wallpapers: settingsPop.wallpapers
            wallpaperPreviewPaths: settingsPop.wallpaperPreviewPaths
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
            writePending: settingsPop.themeWritePending
            pendingKey: settingsPop.pendingThemeKey
            onSetRequested: (key, value) => settingsPop.runSet(key, value)
        }
    }

    Component {
        id: mousePane

        Settings.SettingsMousePane {
            themeState: settingsPop.themeState
            themeWritePending: settingsPop.themeWritePending
            pendingThemeKey: settingsPop.pendingThemeKey
            mouseSettings: settingsPop.mouseSettings
            mouseRuntimeError: settingsPop.mouseRuntimeError
            mouseWritePending: settingsPop.mouseWritePending
            pendingMouseKey: settingsPop.pendingMouseKey
            onThemeSetRequested: (key, value) => settingsPop.runSet(key, value)
            onMouseSetRequested: (key, value) => settingsPop.runMouseSet(key, value)
        }
    }
}
