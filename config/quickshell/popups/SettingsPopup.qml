import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../components" as Components

PanelWindow {
    id: settingsPop
    property bool active: false
    signal close()
    property bool closing: false
    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // ── State ──
    property var themeState: ({})
    property var colorSchemes: []
    property var colorFamilies: []
    property var presets: []
    property var wallpapers: []
    property int selectedCategory: 0
    property string wallpaperDir: "/home/kevin/repos/dotfiles/wallpapers"
    property var categoryNames: ["Presets", "Colors", "Fonts", "Wallpaper", "Icons & Cursors"]
    property var categoryIcons: ["󰒓", "󰏘", "󰛖", "󰋩", "󰍽"]

    onActiveChanged: {
        if (active) { panel.opacity = 0; panel.scale = 0.92; loadState(); settingsOpenAnim.start(); }
        else if (!closing) { closing = true; settingsCloseAnim.start(); }
    }

    // ── Data loading ──
    function loadState() {
        stateProc.running = true;
        listColorsProc.running = true;
        listPresetsProc.running = true;
        listWallpapersProc.running = true;
    }

    Process {
        id: stateProc; command: ["cat", "/home/kevin/repos/dotfiles/themes/state.json"]; running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { stateProc.buf += line; } }
        onExited: {
            try {
                settingsPop.themeState = JSON.parse(buf);
            } catch(e) {}
            buf = "";
        }
    }

    Process {
        id: listColorsProc; running: false
        command: ["bash", "-c", "for f in /home/kevin/repos/dotfiles/themes/colors/*.json; do name=$(basename \"$f\" .json); jq -c --arg name \"$name\" '{schemeName: $name, family: .family, variant: .variant, bg: .colors.bg, fg: .colors.fg, accent: .colors.accent, red: .colors.red, green: .colors.green, blue: .colors.blue, yellow: .colors.yellow, purple: .colors.purple}' \"$f\"; done"]
        property var items: []
        stdout: SplitParser { onRead: (line) => { try { listColorsProc.items.push(JSON.parse(line.trim())); } catch(e) {} } }
        onExited: {
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
            items = [];
        }
    }

    Process {
        id: listPresetsProc; running: false
        command: ["bash", "-c", "for f in /home/kevin/repos/dotfiles/themes/presets/*.json; do name=$(basename \"$f\" .json); jq -c --arg name \"$name\" '{name: $name} + .' \"$f\"; done"]
        property var items: []
        stdout: SplitParser { onRead: (line) => { try { listPresetsProc.items.push(JSON.parse(line.trim())); } catch(e) {} } }
        onExited: { settingsPop.presets = items; items = []; }
    }

    Process {
        id: listWallpapersProc; running: false
        command: ["bash", "-c", "ls -- \"$1\" 2>/dev/null || true", "_", settingsPop.wallpaperDir]
        property var items: []
        stdout: SplitParser { onRead: (line) => { let t = line.trim(); if (t !== "") listWallpapersProc.items.push(t); } }
        onExited: { settingsPop.wallpapers = items; items = []; }
    }

    Process {
        id: dirPickerProc; running: false
        command: ["bash", "-c", "if command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$1\"; else zenity --file-selection --directory --title='Select Wallpaper Directory'; fi", "_", settingsPop.wallpaperDir]
        property string result: ""
        stdout: SplitParser { onRead: (line) => { dirPickerProc.result = line.trim(); } }
        onExited: {
            if (result !== "") {
                settingsPop.wallpaperDir = result;
                listWallpapersProc.items = [];
                listWallpapersProc.running = true;
            }
            result = "";
        }
    }

    // ── Helper functions ──
    function familyDisplayName(name) {
        if (name === "tokyonight") return "Tokyo Night";
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    // ── Apply commands ──
    Process { id: applyProc; running: false }

    function runSet(key, value) {
        applyProc.command = ["/home/kevin/repos/dotfiles/themes/apply-theme", "set", key, value];
        applyProc.running = true;
        reloadTimer.restart();
    }

    function runPreset(name) {
        applyProc.command = ["/home/kevin/repos/dotfiles/themes/apply-theme", "preset", name];
        applyProc.running = true;
        reloadTimer.restart();
    }

    Timer { id: reloadTimer; interval: 1500; onTriggered: loadState() }

    // ── Backdrop ──
    MouseArea {
        anchors.fill: parent; onClicked: settingsPop.close()
        focus: settingsPop.active
        Keys.onEscapePressed: settingsPop.close()
    }

    // ── Animations ──
    SequentialAnimation {
        id: settingsOpenAnim
        ParallelAnimation {
            NumberAnimation { target: panel; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: panel; property: "scale"; to: 1.0; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: settingsCloseAnim
        ParallelAnimation {
            NumberAnimation { target: panel; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
            NumberAnimation { target: panel; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { settingsPop.closing = false; } }
    }

    // ── Panel ──
    Rectangle {
        id: panel
        width: 700; height: 500
        anchors.centerIn: parent
        radius: Theme.popupRadius; color: Theme.bg; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: 0.92
        transformOrigin: Item.Center
        clip: true
        layer.enabled: true

        Row {
            anchors.fill: parent

            // ── Sidebar ──
            Rectangle {
                id: sidebar
                width: 190; height: parent.height
                color: Theme.bg0_h

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    // Header
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36

                        Text {
                            text: "Appearance"
                            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                            color: Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true
                        }
                    }

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Theme.bg3 }
                    Item { Layout.preferredHeight: 4 }

                    // Category items
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            id: catItem
                            required property int index
                            property bool isSelected: settingsPop.selectedCategory === index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: Theme.hoverRadius
                            color: isSelected ? Theme.bg2 : (catArea.containsMouse ? Theme.bg1 : "transparent")
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }

                            Rectangle {
                                visible: catItem.isSelected
                                width: 3; height: 16; radius: 1.5
                                anchors { left: parent.left; leftMargin: 2; verticalCenter: parent.verticalCenter }
                                color: Theme.accent
                            }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                                spacing: 10
                                Text {
                                    text: settingsPop.categoryIcons[catItem.index]
                                    color: catItem.isSelected ? Theme.accent : Theme.fg4
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                                    Layout.alignment: Qt.AlignVCenter
                                }
                                Text {
                                    text: settingsPop.categoryNames[catItem.index]
                                    color: catItem.isSelected ? Theme.fg : Theme.fg3
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.fillWidth: true
                                }
                            }

                            MouseArea {
                                id: catArea; anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: settingsPop.selectedCategory = catItem.index
                            }
                        }
                    }

                    Item { Layout.fillWidth: true; Layout.fillHeight: true }
                }
            }

            // ── Separator ──
            Rectangle { width: 1; height: parent.height; color: Theme.bg3 }

            // ── Detail pane ──
            Item {
                width: parent.width - 191; height: parent.height

                Loader {
                    id: detailLoader
                    anchors { fill: parent; margins: Theme.popupPadding }
                    sourceComponent: {
                        switch (settingsPop.selectedCategory) {
                            case 0: return presetsPane;
                            case 1: return colorsPane;
                            case 2: return fontsPane;
                            case 3: return wallpaperPane;
                            case 4: return iconsPane;
                            default: return null;
                        }
                    }
                }
            }
        }
    }

    // ── Detail: Presets ──
    Component {
        id: presetsPane
        Flickable {
            anchors.fill: parent
            contentHeight: presetsCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: presetsCol; width: parent.width; spacing: 10

                Repeater {
                    model: settingsPop.presets.length
                    delegate: Rectangle {
                        id: presetCard
                        required property int index
                        property var preset: settingsPop.presets[index] || {}
                        property string presetName: preset.name || ""

                        Layout.fillWidth: true
                        Layout.preferredHeight: presetContent.implicitHeight + 24
                        radius: Theme.btnRadius + 2
                        color: presetCardArea.containsMouse ? Theme.bg2 : Theme.bg1
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        border.width: 1
                        border.color: presetCardArea.containsMouse ? Theme.accent : Theme.bg3
                        Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
                        scale: presetCardArea.pressed ? 0.98 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                        transformOrigin: Item.Center

                        ColumnLayout {
                            id: presetContent
                            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
                            spacing: 4

                            Text {
                                text: settingsPop.familyDisplayName(presetCard.presetName)
                                color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                            }

                            Text {
                                text: {
                                    let p = presetCard.preset;
                                    let lines = [];
                                    let keys = Object.keys(p);
                                    for (let i = 0; i < keys.length; i++) {
                                        if (keys[i] !== "name")
                                            lines.push(keys[i].replace(/_/g, " ") + ":  " + p[keys[i]]);
                                    }
                                    return lines.join("\n");
                                }
                                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                wrapMode: Text.WordWrap; Layout.fillWidth: true; lineHeight: 1.4
                            }
                        }

                        MouseArea {
                            id: presetCardArea; anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: settingsPop.runPreset(presetCard.presetName)
                        }
                    }
                }
            }
        }
    }

    // ── Detail: Colors ──
    Component {
        id: colorsPane
        Flickable {
            anchors.fill: parent
            contentHeight: colorsCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: colorsCol; width: parent.width; spacing: 16

                Grid {
                    id: colorGrid
                    Layout.fillWidth: true
                    columns: 3; spacing: 8

                    Repeater {
                        model: settingsPop.colorFamilies.length
                        delegate: Rectangle {
                            id: famCard
                            required property int index
                            property var variant: settingsPop.colorFamilies[index]
                            property bool isActive: settingsPop.themeState.color_scheme === (variant ? variant.schemeName : "")

                            width: (colorGrid.width - 16) / 3; height: 80
                            radius: Theme.btnRadius + 2
                            color: variant ? variant.bg : Theme.bg1
                            border.width: isActive ? 2 : 1
                            border.color: isActive ? (variant ? variant.accent : Theme.accent) : (famArea.containsMouse ? Theme.fg4 : Theme.bg3)
                            Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                            scale: famArea.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            ColumnLayout {
                                anchors { fill: parent; margins: 10 }
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        text: settingsPop.familyDisplayName(famCard.variant ? famCard.variant.family : "")
                                        color: famCard.variant ? famCard.variant.fg : Theme.fg
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                                    }
                                    Text {
                                        text: famCard.variant ? famCard.variant.variant : ""
                                        color: famCard.variant ? famCard.variant.fg : Theme.fg4
                                        opacity: 0.6
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "✓"; visible: famCard.isActive
                                        color: famCard.variant ? famCard.variant.accent : Theme.accent
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                                    }
                                }

                                Row {
                                    spacing: 4
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.accent : Theme.accent; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.red : Theme.red; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.green : Theme.green; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.blue : Theme.blue; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.yellow : Theme.yellow; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.purple : Theme.purple; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                }
                            }

                            MouseArea {
                                id: famArea; anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: settingsPop.runSet("color_scheme", famCard.variant.schemeName)
                            }
                        }
                    }
                }

                // ── Electron / Browser Hint ──
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8

                    Text {
                        text: "ELECTRON / BROWSER HINT"
                        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                    }

                    Row {
                        spacing: 6

                        Rectangle {
                            id: lightHintBtn
                            property bool isActive: settingsPop.themeState.dark_hint === false
                            width: lightHintLabel.implicitWidth + 20; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: isActive ? Theme.accent : (lightHintArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            border.width: 1; border.color: isActive ? Theme.accent : Theme.bg3
                            Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                            scale: lightHintArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Text {
                                id: lightHintLabel; anchors.centerIn: parent; text: "Light"
                                color: lightHintBtn.isActive ? Theme.bg : Theme.fg
                                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            }
                            MouseArea {
                                id: lightHintArea; anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: settingsPop.runSet("dark_hint", "light")
                            }
                        }

                        Rectangle {
                            id: darkHintBtn
                            property bool isActive: settingsPop.themeState.dark_hint !== false
                            width: darkHintLabel.implicitWidth + 20; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: isActive ? Theme.accent : (darkHintArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            border.width: 1; border.color: isActive ? Theme.accent : Theme.bg3
                            Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                            scale: darkHintArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Text {
                                id: darkHintLabel; anchors.centerIn: parent; text: "Dark"
                                color: darkHintBtn.isActive ? Theme.bg : Theme.fg
                                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            }
                            MouseArea {
                                id: darkHintArea; anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: settingsPop.runSet("dark_hint", "dark")
                            }
                        }
                    }

                    Text {
                        text: "Controls Chrome & Electron dark mode independently of color scheme."
                        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
            }
        }
    }

    // ── Detail: Fonts ──
    Component {
        id: fontsPane
        Flickable {
            anchors.fill: parent
            contentHeight: fontsCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: fontsCol; width: parent.width; spacing: 16

                // ── Coding Font ──
                Text { text: "CODING FONT"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                Flow {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: ["JetBrains Mono Nerd Font", "Berkeley Mono", "Recursive Mono", "Fira Code Nerd Font", "Iosevka Nerd Font"]
                        delegate: Rectangle {
                            id: mfBtn
                            required property string modelData; required property int index
                            property bool isCurrent: settingsPop.themeState.mono_font === modelData

                            width: mfLabel.implicitWidth + 16; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: isCurrent ? Theme.accent : (mfArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                            scale: mfArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Text { id: mfLabel; anchors.centerIn: parent; text: mfBtn.modelData.replace(" Nerd Font", ""); color: mfBtn.isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Behavior on color { ColorAnimation { duration: Theme.animHover } } }
                            MouseArea { id: mfArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("mono_font", mfBtn.modelData) }
                        }
                    }
                }

                Row {
                    spacing: 8
                    Text { text: "Size:"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }
                    Rectangle {
                        width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                        color: mfMinus.containsMouse ? Theme.bg2 : Theme.bg1; border.width: 1; border.color: Theme.bg3
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        MouseArea { id: mfMinus; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: { let s = (settingsPop.themeState.mono_font_size || 11) - 1; if (s >= 6) settingsPop.runSet("mono_font_size", String(s)); } }
                    }
                    Text { text: String(settingsPop.themeState.mono_font_size || 11); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; width: 24; horizontalAlignment: Text.AlignHCenter; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }
                    Rectangle {
                        width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                        color: mfPlus.containsMouse ? Theme.bg2 : Theme.bg1; border.width: 1; border.color: Theme.bg3
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        MouseArea { id: mfPlus; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: { let s = (settingsPop.themeState.mono_font_size || 11) + 1; if (s <= 24) settingsPop.runSet("mono_font_size", String(s)); } }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ── System Font ──
                Text { text: "SYSTEM FONT"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                Flow {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: ["Overpass", "Inter", "Noto Sans", "Cantarell", "Source Sans 3"]
                        delegate: Rectangle {
                            id: sfBtn
                            required property string modelData; required property int index
                            property bool isCurrent: settingsPop.themeState.system_font === modelData

                            width: sfLabel.implicitWidth + 16; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: isCurrent ? Theme.accent : (sfArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                            scale: sfArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Text { id: sfLabel; anchors.centerIn: parent; text: sfBtn.modelData; color: sfBtn.isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Behavior on color { ColorAnimation { duration: Theme.animHover } } }
                            MouseArea { id: sfArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("system_font", sfBtn.modelData) }
                        }
                    }
                }

                Row {
                    spacing: 8
                    Text { text: "Size:"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }
                    Rectangle {
                        width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                        color: sfMinus.containsMouse ? Theme.bg2 : Theme.bg1; border.width: 1; border.color: Theme.bg3
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        MouseArea { id: sfMinus; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: { let s = (settingsPop.themeState.font_size || 11) - 1; if (s >= 6) settingsPop.runSet("font_size", String(s)); } }
                    }
                    Text { text: String(settingsPop.themeState.font_size || 11); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; width: 24; horizontalAlignment: Text.AlignHCenter; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }
                    Rectangle {
                        width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                        color: sfPlus.containsMouse ? Theme.bg2 : Theme.bg1; border.width: 1; border.color: Theme.bg3
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        MouseArea { id: sfPlus; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: { let s = (settingsPop.themeState.font_size || 11) + 1; if (s <= 24) settingsPop.runSet("font_size", String(s)); } }
                    }
                }
            }
        }
    }

    // ── Detail: Wallpaper ──
    Component {
        id: wallpaperPane
        Flickable {
            anchors.fill: parent
            contentHeight: wpCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: wpCol; width: parent.width; spacing: 8

                Text {
                    text: "FILTER TO THEME"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Text {
                            text: "Color-grade wallpaper before applying"
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "Uses the active theme palette before sending the image to swww."
                            color: Theme.fg4
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    Components.ToggleSwitch {
                        checked: settingsPop.themeState.filter_wallpaper === true
                        onToggled: settingsPop.runSet(
                            "filter_wallpaper",
                            settingsPop.themeState.filter_wallpaper === true ? "off" : "on"
                        )
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                Text {
                    visible: settingsPop.wallpapers.length === 0
                    text: "No wallpapers found in the selected directory."
                    color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                    Layout.topMargin: 24
                }

                Grid {
                    id: wpGrid
                    Layout.fillWidth: true
                    columns: 3; spacing: 8

                    Repeater {
                        model: settingsPop.wallpapers
                        delegate: Item {
                            id: wpCard
                            required property string modelData; required property int index
                            property bool isCurrent: settingsPop.themeState.wallpaper === settingsPop.wallpaperDir + "/" + modelData

                            width: (wpGrid.width - 16) / 3
                            height: width * 0.65 + 24
                            scale: wpArea.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Column {
                                anchors.fill: parent; spacing: 4

                                Rectangle {
                                    width: parent.width; height: parent.height - 24
                                    radius: 8; clip: true; color: Theme.bg1
                                    border.width: wpCard.isCurrent ? 2 : 1
                                    border.color: wpCard.isCurrent ? Theme.accent : (wpArea.containsMouse ? Theme.fg4 : Theme.bg3)
                                    Behavior on border.color { ColorAnimation { duration: Theme.animHover } }

                                    Image {
                                        anchors.fill: parent; anchors.margins: 1
                                        source: "file://" + settingsPop.wallpaperDir + "/" + wpCard.modelData
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }

                                Text {
                                    width: parent.width; height: 20
                                    text: wpCard.modelData.replace(/\.\w+$/, "")
                                    color: wpCard.isCurrent ? Theme.accent : Theme.fg3
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideMiddle; leftPadding: 4; rightPadding: 4
                                }
                            }

                            MouseArea { id: wpArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: settingsPop.runSet("wallpaper", settingsPop.wallpaperDir + "/" + wpCard.modelData) }
                        }
                    }
                }

                // ── Directory path + picker ──
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; Layout.topMargin: 8 }

                RowLayout {
                    Layout.fillWidth: true; spacing: 8

                    Text {
                        text: settingsPop.wallpaperDir
                        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignVCenter
                        elide: Text.ElideMiddle
                    }

                    Rectangle {
                        width: changeDirLabel.implicitWidth + 16; height: Theme.btnHeight; radius: Theme.btnRadius
                        color: changeDirArea.containsMouse ? Theme.bg2 : Theme.bg1
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        border.width: 1; border.color: Theme.bg3
                        scale: changeDirArea.pressed ? 0.95 : 1.0
                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                        transformOrigin: Item.Center

                        Text { id: changeDirLabel; anchors.centerIn: parent; text: "Change Directory..."; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                        MouseArea { id: changeDirArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: dirPickerProc.running = true }
                    }
                }
            }
        }
    }

    // ── Detail: Icons & Cursors ──
    Component {
        id: iconsPane
        Flickable {
            anchors.fill: parent
            contentHeight: iconsCol.implicitHeight
            clip: true; boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: iconsCol; width: parent.width; spacing: 16

                // ── Icon Theme ──
                Text { text: "ICON THEME"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                Flow {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: ["Neuwaita", "Papirus-Dark", "Papirus", "Papirus-Light", "Adwaita", "hicolor"]
                        delegate: Rectangle {
                            id: itBtn
                            required property string modelData; required property int index
                            property bool isCurrent: settingsPop.themeState.icon_theme === modelData

                            width: itLabel.implicitWidth + 16; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: isCurrent ? Theme.accent : (itArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                            scale: itArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Text { id: itLabel; anchors.centerIn: parent; text: itBtn.modelData; color: itBtn.isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Behavior on color { ColorAnimation { duration: Theme.animHover } } }
                            MouseArea { id: itArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("icon_theme", itBtn.modelData) }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ── Cursor Theme ──
                Text { text: "CURSOR THEME"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                Flow {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: ["Adwaita", "Bibata-Modern-Classic", "Bibata-Modern-Ice", "BreezeX-RosePine-Linux", "BreezeX-RosePineDawn-Linux"]
                        delegate: Rectangle {
                            id: ctBtn
                            required property string modelData; required property int index
                            property bool isCurrent: settingsPop.themeState.cursor_theme === modelData

                            width: ctLabel.implicitWidth + 16; height: Theme.btnHeight; radius: Theme.btnRadius
                            color: isCurrent ? Theme.accent : (ctArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                            scale: ctArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Text { id: ctLabel; anchors.centerIn: parent; text: ctBtn.modelData; color: ctBtn.isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                Behavior on color { ColorAnimation { duration: Theme.animHover } } }
                            MouseArea { id: ctArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("cursor_theme", ctBtn.modelData) }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ── Cursor Size ──
                Row {
                    spacing: 8
                    Text { text: "Cursor Size:"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }
                    Rectangle {
                        width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                        color: csMinus.containsMouse ? Theme.bg2 : Theme.bg1; border.width: 1; border.color: Theme.bg3
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        MouseArea { id: csMinus; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: { let s = (settingsPop.themeState.cursor_size || 24) - 4; if (s >= 16) settingsPop.runSet("cursor_size", String(s)); } }
                    }
                    Text { text: String(settingsPop.themeState.cursor_size || 24); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; width: 28; horizontalAlignment: Text.AlignHCenter; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }
                    Rectangle {
                        width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                        color: csPlus.containsMouse ? Theme.bg2 : Theme.bg1; border.width: 1; border.color: Theme.bg3
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                        MouseArea { id: csPlus; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                            onClicked: { let s = (settingsPop.themeState.cursor_size || 24) + 4; if (s <= 48) settingsPop.runSet("cursor_size", String(s)); } }
                    }
                }
            }
        }
    }
}
