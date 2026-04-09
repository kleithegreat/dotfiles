import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../../components" as Components

Rectangle {
    id: root
    required property string mode
    required property string initialName
    required property var initialPreset
    required property int revision
    required property var themeState
    required property var colorFamilies
    required property var wallpapers
    required property string wallpaperDir
    required property var fontSizeOffsetTargets
    required property var monoFontSizeOffsetTargets
    required property bool busy
    required property string busyAction
    required property string busyTargetName
    required property string errorMessage

    readonly property var systemFontOptions: [
        "Overpass",
        "Inter",
        "Geist",
        "IBM Plex Sans",
        "Rubik",
        "Noto Sans",
        "Cantarell",
        "Source Sans 3",
        "Outfit",
        "SF Pro"
    ]
    readonly property var monoFontOptions: [
        "JetBrains Mono Nerd Font",
        "Berkeley Mono",
        "Commit Mono",
        "Recursive Mono",
        "Fira Code Nerd Font",
        "Iosevka Nerd Font"
    ]
    readonly property var iconThemeOptions: [
        "Neuwaita",
        "Colloid",
        "Colloid-Dark",
        "Colloid-Light",
        "Papirus-Dark",
        "Papirus",
        "Papirus-Light",
        "Adwaita",
        "hicolor"
    ]
    readonly property var cursorThemeOptions: [
        "Adwaita",
        "BreezeX-RosePine-Linux",
        "BreezeX-RosePineDawn-Linux",
        "Bibata-Modern-Classic",
        "Bibata-Modern-Ice",
        "Bibata-Original-Classic",
        "Bibata-Original-Ice"
    ]
    property string wallpaperDraftPath: ""
    property string wallpaperValidationRequestedPath: ""
    property string wallpaperValidationRunningPath: ""
    property string wallpaperPathStatus: "empty"

    signal saveRequested(string name, var presetData)
    signal cancelRequested()

    property string draftName: ""
    property var draftPreset: ({})
    readonly property int includedFieldCount: Object.keys(root.draftPreset || {}).length
    readonly property string effectiveName: root.mode === "edit" ? root.initialName : root.draftName.trim()

    function cloneMap(source) {
        let next = {};
        let keys = Object.keys(source || {});

        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = source[keys[i]];

        return next;
    }

    function inclusionStateLabel(key) {
        return root.hasField(key) ? "Included" : "Ignored";
    }

    function wallpaperFileName(path) {
        let value = String(path || "");
        let parts = value.split("/");

        if (!parts.length)
            return value;
        return parts[parts.length - 1] || value;
    }

    function wallpaperPickerValue() {
        let value = root.wallpaperDraftPath.trim();
        let prefix = root.wallpaperDir + "/";

        if (!value || value.indexOf(prefix) !== 0)
            return null;

        return value.slice(prefix.length);
    }

    function wallpaperStatusText() {
        if (!root.hasField("wallpaper"))
            return "";
        if (root.wallpaperPathStatus === "checking")
            return "Checking path...";
        if (root.wallpaperPathStatus === "relative")
            return "Use an absolute path.";
        if (root.wallpaperPathStatus === "invalid")
            return "Path not found.";
        if (root.wallpaperPathStatus === "valid" && root.wallpaperDraftPath.trim() !== String(root.currentValue("wallpaper") || ""))
            return "Path found. Click Apply to include it.";
        if (root.wallpaperPathStatus === "valid")
            return "Path found.";
        return "";
    }

    function wallpaperStatusColor() {
        if (root.wallpaperPathStatus === "valid")
            return Theme.greenBright;
        if (root.wallpaperPathStatus === "invalid" || root.wallpaperPathStatus === "relative")
            return Theme.redBright;
        return Theme.fg4;
    }

    function requestWallpaperValidation(value) {
        let candidate = String(value || "").trim();
        root.wallpaperValidationRequestedPath = candidate;
        wallpaperValidationTimer.stop();

        if (candidate === "") {
            root.wallpaperValidationRunningPath = "";
            root.wallpaperPathStatus = "empty";
            return;
        }

        if (candidate.charAt(0) !== "/") {
            root.wallpaperValidationRunningPath = "";
            root.wallpaperPathStatus = "relative";
            return;
        }

        root.wallpaperPathStatus = "checking";
        wallpaperValidationTimer.start();
    }

    function syncWallpaperDraft(value) {
        let next = String(value || "");
        root.wallpaperDraftPath = next;
        if (wallpaperInput.text !== next)
            wallpaperInput.text = next;
        root.requestWallpaperValidation(next);
    }

    function commitWallpaperDraft() {
        let candidate = root.wallpaperDraftPath.trim();
        if (candidate === "" || root.wallpaperPathStatus !== "valid")
            return;

        root.setField("wallpaper", candidate);
    }

    function chooseWallpaperOption(name) {
        root.setField("wallpaper", root.wallpaperDir + "/" + name);
    }

    function initialValue(key) {
        let presetValue = (root.initialPreset || {})[key];
        if (presetValue !== undefined)
            return presetValue;
        return root.themeState[key];
    }

    function hasField(key) {
        return (root.draftPreset || {})[key] !== undefined;
    }

    function currentValue(key) {
        return root.hasField(key) ? root.draftPreset[key] : root.initialValue(key);
    }

    function currentIntValue(key, fallback) {
        let parsed = parseInt(root.currentValue(key), 10);
        return isNaN(parsed) ? fallback : parsed;
    }

    function currentBoolValue(key, fallback) {
        let value = root.currentValue(key);
        return value === undefined ? !!fallback : !!value;
    }

    function syncTextInputs() {
        nameInput.text = root.draftName;
        root.syncWallpaperDraft(root.hasField("wallpaper") ? String(root.currentValue("wallpaper") || "") : "");
    }

    function resetFromInitial() {
        root.draftName = root.initialName || "";
        root.draftPreset = root.cloneMap(root.initialPreset || {});
        root.syncTextInputs();
    }

    function setField(key, value) {
        let next = root.cloneMap(root.draftPreset);
        next[key] = value;
        root.draftPreset = next;

        if (key === "wallpaper")
            root.syncWallpaperDraft(value);
    }

    function includeField(key, fallbackValue) {
        let value = root.initialValue(key);
        if (value === undefined)
            value = fallbackValue;
        root.setField(key, value);
    }

    function excludeField(key) {
        let next = root.cloneMap(root.draftPreset);
        delete next[key];
        root.draftPreset = next;

        if (key === "wallpaper")
            root.syncWallpaperDraft("");
    }

    function toggleFieldInclusion(key, fallbackValue) {
        if (root.hasField(key))
            root.excludeField(key);
        else
            root.includeField(key, fallbackValue);
    }

    function stepField(key, delta, minimum, maximum) {
        let next = root.currentIntValue(key, minimum === undefined ? 0 : minimum) + delta;
        if (minimum !== undefined && next < minimum)
            return;
        if (maximum !== undefined && next > maximum)
            return;
        root.setField(key, next);
    }

    function canSave() {
        return !root.busy && root.effectiveName !== "" && root.includedFieldCount > 0;
    }

    function submit() {
        if (!root.canSave())
            return;

        root.saveRequested(root.effectiveName, root.cloneMap(root.draftPreset));
    }

    Component.onCompleted: root.resetFromInitial()
    onRevisionChanged: root.resetFromInitial()

    Timer {
        id: wallpaperValidationTimer
        interval: 120
        repeat: false
        onTriggered: {
            if (root.wallpaperValidationRequestedPath === "" || wallpaperValidationProc.running)
                return;

            root.wallpaperValidationRunningPath = root.wallpaperValidationRequestedPath;
            wallpaperValidationProc.running = true;
        }
    }

    Process {
        id: wallpaperValidationProc
        command: ["bash", "-lc", "test -e \"$1\"", "_", root.wallpaperValidationRunningPath]
        running: false

        onExited: (code) => {
            let checkedPath = root.wallpaperValidationRunningPath;

            if (checkedPath === "")
                return;

            if (root.wallpaperValidationRequestedPath !== checkedPath) {
                if (root.wallpaperValidationRequestedPath !== "")
                    wallpaperValidationTimer.restart();
                return;
            }

            root.wallpaperPathStatus = code === 0 ? "valid" : "invalid";
        }
    }

    radius: Theme.btnRadius + 2
    color: Theme.bg1
    border.width: 1
    border.color: Theme.bg3
    implicitHeight: editorContent.implicitHeight + 24

    ColumnLayout {
        id: editorContent
        anchors.fill: parent
        anchors.margins: 12
        spacing: 12

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true

                Text {
                    text: root.mode === "edit" ? "Edit Preset" : "Create Preset"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    text: String(root.includedFieldCount) + " fields included"
                    color: Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Rectangle {
                width: cancelTopLabel.implicitWidth + 20
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: cancelTopArea.containsMouse ? Theme.bg2 : Theme.bg
                border.width: 1
                border.color: Theme.bg3
                opacity: root.busy ? 0.5 : 1
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                scale: cancelTopArea.pressed ? 0.95 : 1.0
                Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                transformOrigin: Item.Center

                Text {
                    id: cancelTopLabel
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.HoverLayer {
                    id: cancelTopArea
                    anchors.fill: parent
                    enabled: !root.busy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: root.cancelRequested()
                }
            }
        }

        Text {
            text: "Presets are partial overrides. Toggle only the fields you want this preset to change."
            color: Theme.fg4
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Text {
                text: "PRESET NAME"
                color: Theme.fg4
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Rectangle {
                Layout.fillWidth: true
                height: 32
                radius: Theme.btnRadius
                color: root.mode === "edit" ? Theme.bg : Theme.bg2
                border.width: 1
                border.color: root.mode === "create" && nameInput.activeFocus ? Theme.blueBright : Theme.bg3
                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                TextInput {
                    id: nameInput
                    visible: root.mode === "create"
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Theme.fg
                    selectionColor: Theme.blueBright
                    selectedTextColor: Theme.bg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    clip: true
                    onTextEdited: root.draftName = text
                    Keys.onReturnPressed: root.submit()
                }

                Text {
                    visible: root.mode === "create" && !nameInput.text
                    text: "Preset name"
                    color: Theme.fg4
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Text {
                    visible: root.mode === "edit"
                    anchors {
                        left: parent.left
                        leftMargin: 8
                        verticalCenter: parent.verticalCenter
                    }
                    text: root.initialName
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Text {
                visible: root.mode === "edit"
                text: "Rename by creating a new preset, then deleting the old one."
                color: Theme.fg4
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        Text {
            visible: root.errorMessage !== ""
            text: root.errorMessage
            color: Theme.redBright
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "APPEARANCE"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Color scheme"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("color_scheme")
                    onToggled: root.toggleFieldInclusion("color_scheme", root.themeState.color_scheme || "")
                }
            }

            Components.ColorSchemeCards {
                visible: root.hasField("color_scheme")
                Layout.fillWidth: true
                Layout.preferredHeight: visible ? implicitHeight : 0
                model: root.colorFamilies
                currentValue: root.currentValue("color_scheme") || ""
                onActivated: (schemeName) => root.setField("color_scheme", schemeName)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Browser / electron hint"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.inclusionStateLabel("dark_hint")
                    color: Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.hasField("dark_hint")
                    onToggled: root.toggleFieldInclusion("dark_hint", root.themeState.dark_hint !== false)
                }
            }

            RowLayout {
                visible: root.hasField("dark_hint")
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.currentBoolValue("dark_hint", true) ? "Prefer dark browser theme" : "Prefer light browser theme"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.currentBoolValue("dark_hint", true) ? "Dark" : "Light"
                    color: root.currentBoolValue("dark_hint", true) ? Theme.fg3 : Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.currentBoolValue("dark_hint", true)
                    onToggled: root.setField("dark_hint", !root.currentBoolValue("dark_hint", true))
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "WALLPAPER"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Wallpaper path"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("wallpaper")
                    onToggled: root.toggleFieldInclusion("wallpaper", root.themeState.wallpaper || "")
                }
            }

            Rectangle {
                visible: root.hasField("wallpaper")
                Layout.fillWidth: true
                height: 36
                radius: Theme.btnRadius
                color: Theme.bg2
                border.width: 1
                border.color: root.wallpaperPathStatus === "invalid" || root.wallpaperPathStatus === "relative"
                    ? Theme.redBright
                    : (wallpaperInput.activeFocus ? Theme.blueBright : Theme.bg3)
                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                TextInput {
                    id: wallpaperInput
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Theme.fg
                    selectionColor: Theme.blueBright
                    selectedTextColor: Theme.bg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    clip: true
                    onTextEdited: {
                        root.wallpaperDraftPath = text;
                        root.requestWallpaperValidation(text);
                    }
                    Keys.onReturnPressed: root.commitWallpaperDraft()
                }

                Text {
                    visible: !wallpaperInput.text
                    text: "Absolute wallpaper path"
                    color: Theme.fg4
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            RowLayout {
                visible: root.hasField("wallpaper")
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: applyWallpaperLabel.implicitWidth + 18
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: root.wallpaperPathStatus === "valid" && root.wallpaperDraftPath.trim() !== String(root.currentValue("wallpaper") || "")
                        ? (applyWallpaperArea.containsMouse ? Theme.greenBright : Theme.accent)
                        : Theme.bg
                    border.width: 1
                    border.color: root.wallpaperPathStatus === "valid" && root.wallpaperDraftPath.trim() !== String(root.currentValue("wallpaper") || "")
                        ? Theme.accent
                        : Theme.bg3
                    opacity: root.wallpaperPathStatus === "valid" && root.wallpaperDraftPath.trim() !== String(root.currentValue("wallpaper") || "") ? 1 : 0.6
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text {
                        id: applyWallpaperLabel
                        anchors.centerIn: parent
                        text: "Apply"
                        color: root.wallpaperPathStatus === "valid" && root.wallpaperDraftPath.trim() !== String(root.currentValue("wallpaper") || "") ? Theme.bg : Theme.fg4
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        font.bold: root.wallpaperPathStatus === "valid" && root.wallpaperDraftPath.trim() !== String(root.currentValue("wallpaper") || "")
                    }

                    Components.HoverLayer {
                        id: applyWallpaperArea
                        anchors.fill: parent
                        disabled: !(root.wallpaperPathStatus === "valid" && root.wallpaperDraftPath.trim() !== String(root.currentValue("wallpaper") || ""))
                        hoverOpacity: 0
                        pressedOpacity: 0
                        pressedScale: 1.0
                        onClicked: root.commitWallpaperDraft()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: clearWallpaperLabel.implicitWidth + 18
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: clearWallpaperArea.containsMouse ? Theme.bg2 : Theme.bg
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text {
                        id: clearWallpaperLabel
                        anchors.centerIn: parent
                        text: "Clear"
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                    }

                    Components.HoverLayer {
                        id: clearWallpaperArea
                        anchors.fill: parent
                        hoverOpacity: 0
                        pressedOpacity: 0
                        pressedScale: 1.0
                        onClicked: root.excludeField("wallpaper")
                    }
                }

                Item { Layout.fillWidth: true }
            }

            Text {
                visible: root.hasField("wallpaper") && root.wallpaperStatusText() !== ""
                text: root.wallpaperStatusText()
                color: root.wallpaperStatusColor()
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall - 1
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Text {
                visible: root.hasField("wallpaper") && root.wallpapers.length > 0
                text: "Pick from current wallpaper directory"
                color: Theme.fg4
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall - 1
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Components.InlineSelect {
                visible: root.hasField("wallpaper") && root.wallpapers.length > 0
                Layout.fillWidth: true
                model: root.wallpapers
                currentValue: root.wallpaperPickerValue()
                currentText: root.wallpaperPickerValue() || ""
                placeholderText: "Pick a wallpaper file"
                secondaryText: root.wallpapers.length + " files"
                fontFamily: Theme.systemFamily
                maxVisibleItems: 6
                onActivated: (name) => root.chooseWallpaperOption(name)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Filter wallpaper"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.inclusionStateLabel("filter_wallpaper")
                    color: Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.hasField("filter_wallpaper")
                    onToggled: root.toggleFieldInclusion("filter_wallpaper", root.themeState.filter_wallpaper === true)
                }
            }

            RowLayout {
                visible: root.hasField("filter_wallpaper")
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.currentBoolValue("filter_wallpaper", false) ? "Filter wallpaper when applied" : "Do not filter wallpaper when applied"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.currentBoolValue("filter_wallpaper", false) ? "On" : "Off"
                    color: root.currentBoolValue("filter_wallpaper", false) ? Theme.fg3 : Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.currentBoolValue("filter_wallpaper", false)
                    onToggled: root.setField("filter_wallpaper", !root.currentBoolValue("filter_wallpaper", false))
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "FONTS"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "System font"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("system_font")
                    onToggled: root.toggleFieldInclusion("system_font", root.themeState.system_font || "Overpass")
                }
            }

            Components.InlineSelect {
                id: presetSystemFontSelect
                visible: root.hasField("system_font")
                Layout.fillWidth: true
                model: root.systemFontOptions
                currentValue: root.currentValue("system_font")
                currentText: root.currentValue("system_font") || ""
                secondaryText: root.systemFontOptions.length + " fonts"
                fontFamily: Theme.systemFamily
                maxVisibleItems: 7
                onExpandedChanged: {
                    if (expanded)
                        presetMonoFontSelect.expanded = false;
                }
                onActivated: (fontName) => root.setField("system_font", fontName)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "System font size"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("font_size")
                    onToggled: root.toggleFieldInclusion("font_size", root.themeState.font_size || 11)
                }
            }

            Row {
                visible: root.hasField("font_size")
                spacing: 8

                Rectangle {
                    width: 28
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: fontSizeMinus.containsMouse ? Theme.bg2 : Theme.bg
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                    Components.HoverLayer {
                        id: fontSizeMinus
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.stepField("font_size", -1, 6, 24)
                    }
                }

                Text {
                    text: String(root.currentIntValue("font_size", 11))
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSize
                    width: 28
                    horizontalAlignment: Text.AlignHCenter
                    height: Theme.btnHeight
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    width: 28
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: fontSizePlus.containsMouse ? Theme.bg2 : Theme.bg
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                    Components.HoverLayer {
                        id: fontSizePlus
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.stepField("font_size", 1, 6, 24)
                    }
                }
            }
        }

        Repeater {
            model: root.fontSizeOffsetTargets

            delegate: ColumnLayout {
                required property var modelData
                required property int index
                property string fieldKey: modelData.key

                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: modelData.label + " offset"
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                    }

                    Components.ToggleSwitch {
                        checked: root.hasField(fieldKey)
                        onToggled: root.toggleFieldInclusion(fieldKey, root.themeState[fieldKey] === undefined ? 0 : root.themeState[fieldKey])
                    }
                }

                Row {
                    visible: root.hasField(fieldKey)
                    spacing: 8

                    Rectangle {
                        width: 28
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: systemOffsetMinus.containsMouse ? Theme.bg2 : Theme.bg
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                        Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                        Components.HoverLayer {
                            id: systemOffsetMinus
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.stepField(fieldKey, -1)
                        }
                    }

                    Text {
                        text: String(root.currentIntValue(fieldKey, 0))
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSize
                        width: 28
                        horizontalAlignment: Text.AlignHCenter
                        height: Theme.btnHeight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        width: 28
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: systemOffsetPlus.containsMouse ? Theme.bg2 : Theme.bg
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                        Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                        Components.HoverLayer {
                            id: systemOffsetPlus
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.stepField(fieldKey, 1)
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Coding font"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("mono_font")
                    onToggled: root.toggleFieldInclusion("mono_font", root.themeState.mono_font || "JetBrains Mono Nerd Font")
                }
            }

            Components.InlineSelect {
                id: presetMonoFontSelect
                visible: root.hasField("mono_font")
                Layout.fillWidth: true
                model: root.monoFontOptions
                currentValue: root.currentValue("mono_font")
                currentText: root.currentValue("mono_font") ? root.currentValue("mono_font").replace(" Nerd Font", "") : ""
                secondaryText: root.monoFontOptions.length + " fonts"
                fontFamily: Theme.systemFamily
                maxVisibleItems: 6
                textForValue: function(fontName) { return fontName.replace(" Nerd Font", ""); }
                onExpandedChanged: {
                    if (expanded)
                        presetSystemFontSelect.expanded = false;
                }
                onActivated: (fontName) => root.setField("mono_font", fontName)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Coding font size"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("mono_font_size")
                    onToggled: root.toggleFieldInclusion("mono_font_size", root.themeState.mono_font_size || 11)
                }
            }

            Row {
                visible: root.hasField("mono_font_size")
                spacing: 8

                Rectangle {
                    width: 28
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: monoFontSizeMinus.containsMouse ? Theme.bg2 : Theme.bg
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                    Components.HoverLayer {
                        id: monoFontSizeMinus
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.stepField("mono_font_size", -1, 6, 24)
                    }
                }

                Text {
                    text: String(root.currentIntValue("mono_font_size", 11))
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSize
                    width: 28
                    horizontalAlignment: Text.AlignHCenter
                    height: Theme.btnHeight
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    width: 28
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: monoFontSizePlus.containsMouse ? Theme.bg2 : Theme.bg
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                    Components.HoverLayer {
                        id: monoFontSizePlus
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.stepField("mono_font_size", 1, 6, 24)
                    }
                }
            }
        }

        Repeater {
            model: root.monoFontSizeOffsetTargets

            delegate: ColumnLayout {
                required property var modelData
                required property int index
                property string fieldKey: modelData.key

                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: modelData.label + " offset"
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                    }

                    Components.ToggleSwitch {
                        checked: root.hasField(fieldKey)
                        onToggled: root.toggleFieldInclusion(fieldKey, root.themeState[fieldKey] === undefined ? 0 : root.themeState[fieldKey])
                    }
                }

                Row {
                    visible: root.hasField(fieldKey)
                    spacing: 8

                    Rectangle {
                        width: 28
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: offsetMinus.containsMouse ? Theme.bg2 : Theme.bg
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                        Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                        Components.HoverLayer {
                            id: offsetMinus
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.stepField(fieldKey, -1)
                        }
                    }

                    Text {
                        text: String(root.currentIntValue(fieldKey, 0))
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSize
                        width: 28
                        horizontalAlignment: Text.AlignHCenter
                        height: Theme.btnHeight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        width: 28
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: offsetPlus.containsMouse ? Theme.bg2 : Theme.bg
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                        Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                        Components.HoverLayer {
                            id: offsetPlus
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.stepField(fieldKey, 1)
                        }
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "ICONS & CURSORS"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Icon theme"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("icon_theme")
                    onToggled: root.toggleFieldInclusion("icon_theme", root.themeState.icon_theme || "Neuwaita")
                }
            }

            Components.InlineSelect {
                id: presetIconThemeSelect
                visible: root.hasField("icon_theme")
                Layout.fillWidth: true
                model: root.iconThemeOptions
                currentValue: root.currentValue("icon_theme")
                currentText: root.currentValue("icon_theme") || ""
                secondaryText: root.iconThemeOptions.length + " themes"
                fontFamily: Theme.systemFamily
                maxVisibleItems: 7
                onExpandedChanged: {
                    if (expanded)
                        presetCursorThemeSelect.expanded = false;
                }
                onActivated: (value) => root.setField("icon_theme", value)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Cursor theme"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("cursor_theme")
                    onToggled: root.toggleFieldInclusion("cursor_theme", root.themeState.cursor_theme || "Adwaita")
                }
            }

            Components.InlineSelect {
                id: presetCursorThemeSelect
                visible: root.hasField("cursor_theme")
                Layout.fillWidth: true
                model: root.cursorThemeOptions
                currentValue: root.currentValue("cursor_theme")
                currentText: root.currentValue("cursor_theme") || ""
                secondaryText: root.cursorThemeOptions.length + " themes"
                fontFamily: Theme.systemFamily
                maxVisibleItems: 7
                onExpandedChanged: {
                    if (expanded)
                        presetIconThemeSelect.expanded = false;
                }
                onActivated: (value) => root.setField("cursor_theme", value)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Cursor size"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Components.ToggleSwitch {
                    checked: root.hasField("cursor_size")
                    onToggled: root.toggleFieldInclusion("cursor_size", root.themeState.cursor_size || 24)
                }
            }

            Row {
                visible: root.hasField("cursor_size")
                spacing: 8

                Rectangle {
                    width: 28
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: cursorSizeMinus.containsMouse ? Theme.bg2 : Theme.bg
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                    Components.HoverLayer {
                        id: cursorSizeMinus
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.stepField("cursor_size", -4, 16, 48)
                    }
                }

                Text {
                    text: String(root.currentIntValue("cursor_size", 24))
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSize
                    width: 28
                    horizontalAlignment: Text.AlignHCenter
                    height: Theme.btnHeight
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    width: 28
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: cursorSizePlus.containsMouse ? Theme.bg2 : Theme.bg
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                    Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                    Components.HoverLayer {
                        id: cursorSizePlus
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.stepField("cursor_size", 4, 16, 48)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "HYPRLAND"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Repeater {
            model: [
                { key: "hypr_gaps_in", label: "Inner gaps", fallback: 4, minimum: 0, step: 1 },
                { key: "hypr_gaps_out", label: "Outer gaps", fallback: 6, minimum: 0, step: 1 },
                { key: "hypr_border_size", label: "Border size", fallback: 0, minimum: 0, step: 1 },
                { key: "hypr_rounding", label: "Rounding", fallback: 8, minimum: 0, step: 1 },
                { key: "hypr_blur_size", label: "Blur size", fallback: 3, minimum: 1, step: 1 },
                { key: "hypr_blur_passes", label: "Blur passes", fallback: 4, minimum: 1, step: 1 }
            ]

            delegate: ColumnLayout {
                required property var modelData
                required property int index

                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: modelData.label
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                    }

                    Components.ToggleSwitch {
                        checked: root.hasField(modelData.key)
                        onToggled: root.toggleFieldInclusion(
                            modelData.key,
                            root.themeState[modelData.key] === undefined ? modelData.fallback : root.themeState[modelData.key]
                        )
                    }
                }

                Row {
                    visible: root.hasField(modelData.key)
                    spacing: 8

                    Rectangle {
                        width: 28
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: hyprIntMinus.containsMouse ? Theme.bg2 : Theme.bg
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                        Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                        Components.HoverLayer {
                            id: hyprIntMinus
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.stepField(modelData.key, -(modelData.step || 1), modelData.minimum)
                        }
                    }

                    Text {
                        text: String(root.currentIntValue(modelData.key, modelData.minimum))
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSize
                        width: 28
                        horizontalAlignment: Text.AlignHCenter
                        height: Theme.btnHeight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        width: 28
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: hyprIntPlus.containsMouse ? Theme.bg2 : Theme.bg
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                        Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                        Components.HoverLayer {
                            id: hyprIntPlus
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.stepField(modelData.key, modelData.step || 1, modelData.minimum)
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Enable blur"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.inclusionStateLabel("hypr_blur_enabled")
                    color: Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.hasField("hypr_blur_enabled")
                    onToggled: root.toggleFieldInclusion("hypr_blur_enabled", root.themeState.hypr_blur_enabled === true)
                }
            }

            RowLayout {
                visible: root.hasField("hypr_blur_enabled")
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.currentBoolValue("hypr_blur_enabled", false) ? "Enable blur when applied" : "Disable blur when applied"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.currentBoolValue("hypr_blur_enabled", false) ? "On" : "Off"
                    color: root.currentBoolValue("hypr_blur_enabled", false) ? Theme.fg3 : Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.currentBoolValue("hypr_blur_enabled", false)
                    onToggled: root.setField("hypr_blur_enabled", !root.currentBoolValue("hypr_blur_enabled", false))
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "Enable animations"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.inclusionStateLabel("hypr_animations_enabled")
                    color: Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.hasField("hypr_animations_enabled")
                    onToggled: root.toggleFieldInclusion("hypr_animations_enabled", root.themeState.hypr_animations_enabled !== false)
                }
            }

            RowLayout {
                visible: root.hasField("hypr_animations_enabled")
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: root.currentBoolValue("hypr_animations_enabled", true) ? "Enable animations when applied" : "Disable animations when applied"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.currentBoolValue("hypr_animations_enabled", true) ? "On" : "Off"
                    color: root.currentBoolValue("hypr_animations_enabled", true) ? Theme.fg3 : Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.currentBoolValue("hypr_animations_enabled", true)
                    onToggled: root.setField("hypr_animations_enabled", !root.currentBoolValue("hypr_animations_enabled", true))
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.busy ? (
                    root.busyAction === "delete"
                        ? "Deleting " + root.busyTargetName + "…"
                        : "Saving " + root.busyTargetName + "…"
                ) : ""
                color: Theme.fg4
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Rectangle {
                width: cancelBottomLabel.implicitWidth + 20
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: cancelBottomArea.containsMouse ? Theme.bg2 : Theme.bg
                border.width: 1
                border.color: Theme.bg3
                opacity: root.busy ? 0.5 : 1
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                scale: cancelBottomArea.pressed ? 0.95 : 1.0
                Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                transformOrigin: Item.Center

                Text {
                    id: cancelBottomLabel
                    anchors.centerIn: parent
                    text: "Cancel"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.HoverLayer {
                    id: cancelBottomArea
                    anchors.fill: parent
                    enabled: !root.busy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: root.cancelRequested()
                }
            }

            Rectangle {
                width: saveLabel.implicitWidth + 24
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: root.canSave() ? (saveArea.containsMouse ? Theme.greenBright : Theme.accent) : Theme.bg2
                border.width: 1
                border.color: root.canSave() ? Theme.accent : Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                scale: saveArea.pressed ? 0.95 : 1.0
                Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                transformOrigin: Item.Center

                Text {
                    id: saveLabel
                    anchors.centerIn: parent
                    text: root.busy ? "Working..." : (root.mode === "edit" ? "Save Changes" : "Create Preset")
                    color: root.canSave() ? Theme.bg : Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: root.canSave()
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                }

                Components.HoverLayer {
                    id: saveArea
                    anchors.fill: parent
                    enabled: root.canSave()
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: root.submit()
                }
            }
        }
    }
}
