import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var presets
    required property var themeState
    required property var colorFamilies
    required property var wallpapers
    required property string wallpaperDir
    required property var fontSizeOffsetTargets
    required property var monoFontSizeOffsetTargets
    required property bool presetCommandRunning
    required property string presetCommandAction
    required property string presetCommandTargetName
    required property string presetCommandError
    required property int presetMutationToken

    signal presetActivated(string name)
    signal presetSaveRequested(string name, var presetData)
    signal presetDeleteRequested(string name)

    property bool editorOpen: false
    property string editorMode: "create"
    property string editorName: ""
    property var editorPreset: ({})
    property int editorRevision: 0
    property string pendingDeleteName: ""
    property int handledMutationToken: presetMutationToken
    readonly property var monoFontOffsetKeys: [
        "alacritty_mono_font_size_offset",
        "ghostty_mono_font_size_offset",
        "gtk_mono_font_size_offset",
        "neovide_mono_font_size_offset",
        "qt_mono_font_size_offset",
        "vscode_mono_font_size_offset",
        "zed_mono_font_size_offset"
    ]
    readonly property var fontSizeOffsetKeys: [
        "quickshell_font_size_offset",
        "gtk_font_size_offset",
        "qt_font_size_offset"
    ]
    readonly property var fontOffsetKeys: root.monoFontOffsetKeys.concat(root.fontSizeOffsetKeys)
    readonly property var hyprIntKeys: [
        "hypr_gaps_in",
        "hypr_gaps_out",
        "hypr_border_size",
        "hypr_rounding",
        "hypr_blur_size",
        "hypr_blur_passes"
    ]

    function familyDisplayName(name) {
        if (name === "tokyonight")
            return "Tokyo Night";
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function cloneMap(source) {
        let next = {};
        let keys = Object.keys(source || {});

        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = source[keys[i]];

        return next;
    }

    function capitalizeWord(value) {
        let text = String(value || "");
        if (!text)
            return "";
        return text.charAt(0).toUpperCase() + text.slice(1);
    }

    function basename(path) {
        let value = String(path || "");
        let parts = value.split("/");

        if (!parts.length)
            return value;
        return parts[parts.length - 1] || value;
    }

    function shortFontName(name) {
        return String(name || "").replace(/ Nerd Font$/, "");
    }

    function formatColorSchemeName(name) {
        let value = String(name || "");
        let parts = value.split("-");

        if (parts.length < 2)
            return root.familyDisplayName(value);

        return root.familyDisplayName(parts.slice(0, parts.length - 1).join("-")) + " " + root.capitalizeWord(parts[parts.length - 1]);
    }

    function presetFieldKeys(preset) {
        let keys = Object.keys(preset || {});
        let filteredKeys = [];

        for (let i = 0; i < keys.length; i++) {
            if (keys[i] !== "name")
                filteredKeys.push(keys[i]);
        }

        return filteredKeys;
    }

    function presetFieldCount(preset) {
        return root.presetFieldKeys(preset).length;
    }

    function presetFieldCountLabel(preset) {
        let count = root.presetFieldCount(preset);
        return count === 1 ? "1 field" : String(count) + " fields";
    }

    function countDefinedKeys(preset, keys) {
        let data = preset || {};
        let count = 0;

        for (let i = 0; i < keys.length; i++) {
            if (data[keys[i]] !== undefined)
                count += 1;
        }

        return count;
    }

    function describeSection(label, values) {
        if (!values.length)
            return "";
        return label + ": " + values.join(", ");
    }

    function presetSummary(preset) {
        let data = preset || {};
        let sections = [];
        let appearance = [];
        let wallpaper = [];
        let fonts = [];
        let icons = [];
        let hypr = [];
        let fontOffsetCount = root.countDefinedKeys(data, root.fontOffsetKeys);
        let hyprTweakCount = root.countDefinedKeys(data, root.hyprIntKeys);

        if (data.color_scheme !== undefined)
            appearance.push(root.formatColorSchemeName(data.color_scheme));
        if (data.dark_hint !== undefined)
            appearance.push(data.dark_hint ? "Dark UI" : "Light UI");
        if (appearance.length)
            sections.push(root.describeSection("Appearance", appearance));

        if (data.wallpaper !== undefined)
            wallpaper.push(root.basename(data.wallpaper));
        if (data.filter_wallpaper !== undefined)
            wallpaper.push(data.filter_wallpaper ? "Filtered" : "Unfiltered");
        if (wallpaper.length)
            sections.push(root.describeSection("Wallpaper", wallpaper));

        if (data.system_font !== undefined)
            fonts.push("UI " + root.shortFontName(data.system_font));
        if (data.mono_font !== undefined)
            fonts.push("Mono " + root.shortFontName(data.mono_font));
        if (data.font_size !== undefined)
            fonts.push("UI size " + data.font_size);
        if (data.mono_font_size !== undefined)
            fonts.push("Mono size " + data.mono_font_size);
        if (fontOffsetCount > 0)
            fonts.push("+" + fontOffsetCount + " offsets");
        if (fonts.length)
            sections.push(root.describeSection("Fonts", fonts));

        if (data.icon_theme !== undefined)
            icons.push(data.icon_theme);
        if (data.cursor_theme !== undefined)
            icons.push(data.cursor_theme);
        if (data.cursor_size !== undefined)
            icons.push(String(data.cursor_size) + " px");
        if (icons.length)
            sections.push(root.describeSection("Icons", icons));

        if (hyprTweakCount > 0)
            hypr.push(String(hyprTweakCount) + " tweaks");
        if (data.hypr_blur_enabled !== undefined)
            hypr.push(data.hypr_blur_enabled ? "Blur on" : "Blur off");
        if (data.hypr_animations_enabled !== undefined)
            hypr.push(data.hypr_animations_enabled ? "Animations on" : "Animations off");
        if (hypr.length)
            sections.push(root.describeSection("Hyprland", hypr));

        if (sections.length > 3)
            return sections.slice(0, 3).join("  •  ") + "  •  +" + String(sections.length - 3) + " more";
        return sections.join("  •  ");
    }

    function editorPresetFor(preset) {
        let next = root.cloneMap(preset || {});
        delete next.name;
        return next;
    }

    function closeEditor() {
        root.editorOpen = false;
        root.editorMode = "create";
        root.editorName = "";
        root.editorPreset = ({});
    }

    function openCreateEditor() {
        root.pendingDeleteName = "";
        root.editorMode = "create";
        root.editorName = "";
        root.editorPreset = ({});
        root.editorRevision += 1;
        root.editorOpen = true;
    }

    function openEditEditor(preset) {
        root.pendingDeleteName = "";
        root.editorMode = "edit";
        root.editorName = preset.name || "";
        root.editorPreset = root.editorPresetFor(preset);
        root.editorRevision += 1;
        root.editorOpen = true;
    }

    onPresetMutationTokenChanged: {
        if (presetMutationToken === handledMutationToken)
            return;

        handledMutationToken = presetMutationToken;
        pendingDeleteName = "";
        closeEditor();
    }

    anchors.fill: parent
    contentWidth: width
    contentHeight: presetsCol.implicitHeight
    clip: true

    ColumnLayout {
        id: presetsCol
        width: root.width
        spacing: 12

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/adjustments.svg"; color: Theme.fg }
            Text { text: "Presets"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Click a preset card to apply it. Edit and delete are inline."
                color: Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Rectangle {
                width: createLabel.implicitWidth + 20
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: createArea.containsMouse ? Theme.greenBright : Theme.accent
                border.width: 1
                border.color: Theme.accent
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                scale: createArea.pressed ? 0.95 : 1.0
                Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                transformOrigin: Item.Center

                Text {
                    id: createLabel
                    anchors.centerIn: parent
                    text: "Save Current State"
                    color: Theme.bg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                Components.HoverLayer {
                    id: createArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: root.openCreateEditor()
                }
            }
        }

        Text {
            visible: !root.editorOpen
            text: "Create presets as deltas: include only the fields you want to override."
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        SettingsPresetEditor {
            visible: root.editorOpen
            Layout.fillWidth: true
            Layout.preferredHeight: visible ? implicitHeight : 0
            mode: root.editorMode
            initialName: root.editorName
            initialPreset: root.editorPreset
            revision: root.editorRevision
            themeState: root.themeState
            colorFamilies: root.colorFamilies
            wallpapers: root.wallpapers
            wallpaperDir: root.wallpaperDir
            fontSizeOffsetTargets: root.fontSizeOffsetTargets
            monoFontSizeOffsetTargets: root.monoFontSizeOffsetTargets
            busy: root.presetCommandRunning
            busyAction: root.presetCommandAction
            busyTargetName: root.presetCommandTargetName
            errorMessage: root.presetCommandError
            onSaveRequested: (name, presetData) => root.presetSaveRequested(name, presetData)
            onCancelRequested: root.closeEditor()
        }

        Text {
            visible: !root.editorOpen && root.presetCommandError !== ""
            text: root.presetCommandError
            color: Theme.redBright
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Repeater {
            model: root.presets.length

            delegate: Rectangle {
                id: presetCard
                required property int index
                property var preset: root.presets[index] || ({})
                property string presetName: preset.name || ""
                property int presetFieldCount: root.presetFieldCount(preset)
                property string presetFieldCountText: root.presetFieldCountLabel(preset)
                property string presetSummaryText: root.presetSummary(preset)

                Layout.fillWidth: true
                Layout.preferredHeight: presetContent.implicitHeight + 24
                radius: Theme.btnRadius + 2
                color: presetCardArea.containsMouse ? Theme.bg2 : Theme.bg1
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                border.width: 1
                border.color: presetCardArea.containsMouse ? Theme.accent : Theme.bg3
                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                scale: presetCardArea.pressed ? 0.98 : 1.0
                Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                transformOrigin: Item.Center

                Components.HoverLayer {
                    id: presetCardArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: root.presetActivated(presetCard.presetName)
                }

                ColumnLayout {
                    id: presetContent
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        ColumnLayout {
                            spacing: 1
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0

                            Text {
                                text: presetCard.presetName
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }

                            Text {
                                text: presetCard.presetFieldCountText
                                color: Theme.fg4
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            width: editLabel.implicitWidth + 18
                            height: Theme.btnHeight
                            radius: Theme.btnRadius
                            color: editArea.containsMouse ? Theme.bg3 : Theme.bg
                            border.width: 1
                            border.color: Theme.bg3
                            Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            scale: editArea.pressed ? 0.95 : 1.0
                            Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            transformOrigin: Item.Center

                            Text {
                                id: editLabel
                                anchors.centerIn: parent
                                text: "Edit"
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                            }

                            Components.HoverLayer {
                                id: editArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true

                                hoverOpacity: 0

                                pressedOpacity: 0

                                pressedScale: 1.0
                                onClicked: root.openEditEditor(presetCard.preset)
                            }
                        }

                        Rectangle {
                            width: deleteLabel.implicitWidth + 18
                            height: Theme.btnHeight
                            radius: Theme.btnRadius
                            color: {
                                if (root.presetCommandRunning && root.presetCommandAction === "delete" && root.presetCommandTargetName === presetCard.presetName)
                                    return Theme.redBright;
                                if (root.pendingDeleteName === presetCard.presetName)
                                    return Theme.redBright;
                                return deleteArea.containsMouse ? Theme.bg2 : Theme.bg;
                            }
                            border.width: 1
                            border.color: root.pendingDeleteName === presetCard.presetName ? Theme.redBright : Theme.bg3
                            Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            scale: deleteArea.pressed ? 0.95 : 1.0
                            Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            transformOrigin: Item.Center

                            Text {
                                id: deleteLabel
                                anchors.centerIn: parent
                                text: {
                                    if (root.presetCommandRunning && root.presetCommandAction === "delete" && root.presetCommandTargetName === presetCard.presetName)
                                        return "Deleting...";
                                    return root.pendingDeleteName === presetCard.presetName ? "Confirm" : "Delete";
                                }
                                color: root.pendingDeleteName === presetCard.presetName ? Theme.bg : Theme.fg4
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: root.pendingDeleteName === presetCard.presetName
                            }

                            Components.HoverLayer {
                                id: deleteArea
                                anchors.fill: parent
                                enabled: !root.presetCommandRunning
                                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                hoverEnabled: true

                                hoverOpacity: 0

                                pressedOpacity: 0

                                pressedScale: 1.0
                                onClicked: {
                                    if (root.pendingDeleteName === presetCard.presetName)
                                        root.presetDeleteRequested(presetCard.presetName);
                                    else
                                        root.pendingDeleteName = presetCard.presetName;
                                }
                            }
                        }
                    }

                    Text {
                        visible: presetCard.presetSummaryText !== ""
                        text: presetCard.presetSummaryText
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }
        }
    }
}
