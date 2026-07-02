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

    property string wallpaperDraftPath: ""
    property string wallpaperValidationRequestedPath: ""
    property string wallpaperValidationRunningPath: ""
    property string wallpaperPathStatus: "empty"
    readonly property bool wallpaperApplyReady: root.wallpaperPathStatus === "valid"
        && root.wallpaperDraftPath.trim() !== String(root.currentValue("wallpaper") || "")

    signal saveRequested(string name, var presetData)
    signal cancelRequested()

    HyprOptionCatalog { id: hyprOptionCatalog }

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
        if (root.wallpaperApplyReady)
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

    // Label + inclusion ToggleSwitch header shared by every preset field editor.
    component InclusionRow: RowLayout {
        id: inclusionRow

        required property string label
        required property string fieldKey
        required property var fallback
        property bool showState: false

        Layout.fillWidth: true
        spacing: 8

        Text {
            text: inclusionRow.label
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
        }

        Text {
            visible: inclusionRow.showState
            text: root.inclusionStateLabel(inclusionRow.fieldKey)
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
        }

        Components.ToggleSwitch {
            checked: root.hasField(inclusionRow.fieldKey)
            onToggled: root.toggleFieldInclusion(inclusionRow.fieldKey, inclusionRow.fallback)
        }
    }

    component BoolFieldEditor: ColumnLayout {
        id: boolEditor

        required property string label
        required property string fieldKey
        required property bool inclusionFallback
        required property bool boolFallback
        required property string onLabel
        required property string offLabel
        property string onStateText: "On"
        property string offStateText: "Off"
        readonly property bool value: root.currentBoolValue(fieldKey, boolFallback)

        Layout.fillWidth: true
        spacing: 8

        InclusionRow {
            label: boolEditor.label
            fieldKey: boolEditor.fieldKey
            fallback: boolEditor.inclusionFallback
            showState: true
        }

        RowLayout {
            visible: root.hasField(boolEditor.fieldKey)
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: boolEditor.value ? boolEditor.onLabel : boolEditor.offLabel
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Text {
                text: boolEditor.value ? boolEditor.onStateText : boolEditor.offStateText
                color: boolEditor.value ? Theme.fg3 : Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Components.ToggleSwitch {
                checked: boolEditor.value
                onToggled: root.setField(boolEditor.fieldKey, !boolEditor.value)
            }
        }
    }

    component IntFieldEditor: ColumnLayout {
        id: intEditor

        required property string label
        required property string fieldKey
        required property var inclusionFallback
        required property int displayFallback
        property int step: 1
        property var minimum
        property var maximum

        Layout.fillWidth: true
        spacing: 8

        InclusionRow {
            label: intEditor.label
            fieldKey: intEditor.fieldKey
            fallback: intEditor.inclusionFallback
        }

        Components.ValueStepper {
            visible: root.hasField(intEditor.fieldKey)
            baseColor: Theme.bg
            valueText: String(root.currentIntValue(intEditor.fieldKey, intEditor.displayFallback))
            valueWidth: 28
            onDecrement: root.stepField(intEditor.fieldKey, -intEditor.step, intEditor.minimum, intEditor.maximum)
            onIncrement: root.stepField(intEditor.fieldKey, intEditor.step, intEditor.minimum, intEditor.maximum)
        }
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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    text: String(root.includedFieldCount) + " fields included"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Components.ActionButton {
                text: "Cancel"
                baseColor: Theme.bg
                hoverColor: Theme.bg2
                disabledOpacity: 0.5
                enabled: !root.busy
                onClicked: root.cancelRequested()
            }
        }

        Text {
            text: "Presets are partial overrides. Toggle only the fields you want this preset to change."
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 6

            Components.SectionLabel { text: "PRESET NAME" }

            Rectangle {
                Layout.fillWidth: true
                height: 32
                radius: Theme.btnRadius
                color: root.mode === "edit" ? Theme.bg : Theme.bg2
                border.width: 1
                border.color: root.mode === "create" && nameInput.activeFocus ? Theme.blueBright : Theme.bg3
                Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

                TextInput {
                    id: nameInput
                    visible: root.mode === "create"
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Theme.fg
                    selectionColor: Theme.blueBright
                    selectedTextColor: Theme.bg
                    font.family: Theme.fontFamily
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
                    font.family: Theme.fontFamily
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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            Text {
                visible: root.mode === "edit"
                text: "Rename by creating a new preset, then deleting the old one."
                color: Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        Text {
            visible: root.errorMessage !== ""
            text: root.errorMessage
            color: Theme.redBright
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Components.Divider {}

        Components.SectionLabel { text: "APPEARANCE" }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            InclusionRow {
                label: "Color scheme"
                fieldKey: "color_scheme"
                fallback: root.themeState.color_scheme || ""
            }

            Components.ColorSchemeCards {
                visible: root.hasField("color_scheme")
                Layout.fillWidth: true
                model: root.colorFamilies
                currentValue: root.currentValue("color_scheme") || ""
                onActivated: (schemeName) => root.setField("color_scheme", schemeName)
            }
        }

        BoolFieldEditor {
            label: "Browser / electron hint"
            fieldKey: "dark_hint"
            inclusionFallback: root.themeState.dark_hint !== false
            boolFallback: true
            onLabel: "Prefer dark browser theme"
            offLabel: "Prefer light browser theme"
            onStateText: "Dark"
            offStateText: "Light"
        }

        Components.Divider {}

        Components.SectionLabel { text: "WALLPAPER" }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            InclusionRow {
                label: "Wallpaper path"
                fieldKey: "wallpaper"
                fallback: root.themeState.wallpaper || ""
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
                Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

                TextInput {
                    id: wallpaperInput
                    anchors.fill: parent
                    anchors.margins: 8
                    color: Theme.fg
                    selectionColor: Theme.blueBright
                    selectedTextColor: Theme.bg
                    font.family: Theme.fontFamily
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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }
            }

            RowLayout {
                visible: root.hasField("wallpaper")
                Layout.fillWidth: true
                spacing: 8

                Components.ActionButton {
                    text: "Apply"
                    paddingH: 9
                    baseColor: root.wallpaperApplyReady ? Theme.accent : Theme.bg
                    hoverColor: root.wallpaperApplyReady ? Theme.greenBright : Theme.bg
                    borderColor: root.wallpaperApplyReady ? Theme.accent : Theme.bg3
                    textColor: root.wallpaperApplyReady ? Theme.bg : Theme.fg4
                    fontBold: root.wallpaperApplyReady
                    disabledOpacity: 0.6
                    enabled: root.wallpaperApplyReady
                    onClicked: root.commitWallpaperDraft()
                }

                Components.ActionButton {
                    text: "Clear"
                    paddingH: 9
                    baseColor: Theme.bg
                    hoverColor: Theme.bg2
                    onClicked: root.excludeField("wallpaper")
                }

                Item { Layout.fillWidth: true }
            }

            Text {
                visible: root.hasField("wallpaper") && root.wallpaperStatusText() !== ""
                text: root.wallpaperStatusText()
                color: root.wallpaperStatusColor()
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMini
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Text {
                visible: root.hasField("wallpaper") && root.wallpapers.length > 0
                text: "Pick from current wallpaper directory"
                color: Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMini
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
                fontFamily: Theme.fontFamily
                maxVisibleItems: 6
                onActivated: (name) => root.chooseWallpaperOption(name)
            }
        }

        BoolFieldEditor {
            label: "Filter wallpaper"
            fieldKey: "filter_wallpaper"
            inclusionFallback: root.themeState.filter_wallpaper === true
            boolFallback: false
            onLabel: "Filter wallpaper when applied"
            offLabel: "Do not filter wallpaper when applied"
        }

        Components.Divider {}

        Components.SectionLabel { text: "FONTS" }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            InclusionRow {
                label: "System font"
                fieldKey: "system_font"
                fallback: root.themeState.system_font || "Overpass"
            }

            Components.InlineSelect {
                id: presetSystemFontSelect
                visible: root.hasField("system_font")
                Layout.fillWidth: true
                model: ShellOptions.systemFontOptions
                currentValue: root.currentValue("system_font")
                currentText: root.currentValue("system_font") || ""
                secondaryText: ShellOptions.systemFontOptions.length + " fonts"
                isOptionDisabled: function(fontName) { return ShellOptions.isFontUnavailable(fontName); }
                fontFamily: Theme.fontFamily
                maxVisibleItems: 7
                onExpandedChanged: {
                    if (expanded)
                        presetMonoFontSelect.expanded = false;
                }
                onActivated: (fontName) => root.setField("system_font", fontName)
            }
        }

        IntFieldEditor {
            label: "System font size"
            fieldKey: "font_size"
            inclusionFallback: root.themeState.font_size || 11
            displayFallback: 11
            minimum: 6
            maximum: 24
        }

        Repeater {
            model: root.fontSizeOffsetTargets

            delegate: IntFieldEditor {
                required property var modelData

                label: modelData.label + " offset"
                fieldKey: modelData.key
                inclusionFallback: root.themeState[modelData.key] === undefined ? 0 : root.themeState[modelData.key]
                displayFallback: 0
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            InclusionRow {
                label: "Coding font"
                fieldKey: "mono_font"
                fallback: root.themeState.mono_font || ShellOptions.monoFontValue("JetBrains Mono Nerd Font")
            }

            Components.InlineSelect {
                id: presetMonoFontSelect
                visible: root.hasField("mono_font")
                Layout.fillWidth: true
                model: ShellOptions.presetMonoFontOptions
                currentValue: root.currentValue("mono_font")
                currentText: root.currentValue("mono_font") ? ShellOptions.monoFontLabel(root.currentValue("mono_font")) : ""
                secondaryText: ShellOptions.presetMonoFontOptions.length + " fonts"
                matchesCurrent: function(fontName, currentValue) { return ShellOptions.monoFontOptionMatchesCurrent(fontName, currentValue); }
                isOptionDisabled: function(fontName) { return ShellOptions.isMonoFontUnavailable(fontName); }
                fontFamily: Theme.fontFamily
                maxVisibleItems: 6
                textForValue: function(fontName) { return ShellOptions.monoFontLabel(fontName); }
                onExpandedChanged: {
                    if (expanded)
                        presetSystemFontSelect.expanded = false;
                }
                onActivated: (fontName) => root.setField("mono_font", ShellOptions.monoFontValue(fontName))
            }
        }

        IntFieldEditor {
            label: "Coding font size"
            fieldKey: "mono_font_size"
            inclusionFallback: root.themeState.mono_font_size || 11
            displayFallback: 11
            minimum: 6
            maximum: 24
        }

        Repeater {
            model: root.monoFontSizeOffsetTargets

            delegate: IntFieldEditor {
                required property var modelData

                label: modelData.label + " offset"
                fieldKey: modelData.key
                inclusionFallback: root.themeState[modelData.key] === undefined ? 0 : root.themeState[modelData.key]
                displayFallback: 0
            }
        }

        Components.Divider {}

        Components.SectionLabel { text: "ICONS & CURSORS" }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            InclusionRow {
                label: "Icon theme"
                fieldKey: "icon_theme"
                fallback: root.themeState.icon_theme || "Neuwaita"
            }

            Components.IconThemeCards {
                visible: root.hasField("icon_theme")
                Layout.fillWidth: true
                model: ShellOptions.iconThemeOptions
                currentValue: root.currentValue("icon_theme") || ""
                onActivated: (value) => root.setField("icon_theme", value)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            InclusionRow {
                label: "Cursor theme"
                fieldKey: "cursor_theme"
                fallback: root.themeState.cursor_theme || "Adwaita"
            }

            Components.InlineSelect {
                visible: root.hasField("cursor_theme")
                Layout.fillWidth: true
                model: ShellOptions.cursorThemeOptions
                currentValue: root.currentValue("cursor_theme")
                currentText: root.currentValue("cursor_theme") || ""
                secondaryText: ShellOptions.cursorThemeOptions.length + " themes"
                fontFamily: Theme.fontFamily
                maxVisibleItems: 7
                onActivated: (value) => root.setField("cursor_theme", value)
            }
        }

        IntFieldEditor {
            label: "Cursor size"
            fieldKey: "cursor_size"
            inclusionFallback: root.themeState.cursor_size || 24
            displayFallback: 24
            step: 4
            minimum: 16
            maximum: 48
        }

        Components.Divider {}

        Components.SectionLabel { text: "HYPRLAND" }

        Repeater {
            model: hyprOptionCatalog.intOptions

            delegate: IntFieldEditor {
                required property var modelData

                label: modelData.label
                fieldKey: modelData.key
                inclusionFallback: root.themeState[modelData.key] === undefined ? modelData.fallback : root.themeState[modelData.key]
                displayFallback: modelData.minimum
                step: modelData.step || 1
                minimum: modelData.minimum
            }
        }

        BoolFieldEditor {
            label: "Enable blur"
            fieldKey: "hypr_blur_enabled"
            inclusionFallback: root.themeState.hypr_blur_enabled === true
            boolFallback: false
            onLabel: "Enable blur when applied"
            offLabel: "Disable blur when applied"
        }

        BoolFieldEditor {
            label: "Enable animations"
            fieldKey: "hypr_animations_enabled"
            inclusionFallback: root.themeState.hypr_animations_enabled !== false
            boolFallback: true
            onLabel: "Enable animations when applied"
            offLabel: "Disable animations when applied"
        }

        Components.Divider {}

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
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Components.ActionButton {
                text: "Cancel"
                baseColor: Theme.bg
                hoverColor: Theme.bg2
                disabledOpacity: 0.5
                enabled: !root.busy
                onClicked: root.cancelRequested()
            }

            Components.ActionButton {
                text: root.busy ? "Working..." : (root.mode === "edit" ? "Save Changes" : "Create Preset")
                baseColor: root.canSave() ? Theme.accent : Theme.bg2
                hoverColor: root.canSave() ? Theme.greenBright : Theme.bg2
                borderColor: root.canSave() ? Theme.accent : Theme.bg3
                textColor: root.canSave() ? Theme.bg : Theme.fg4
                disabledOpacity: 1
                fontBold: root.canSave()
                enabled: root.canSave()
                onClicked: root.submit()
            }
        }
    }
}
