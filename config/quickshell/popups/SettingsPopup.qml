import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

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
    property string currentFamily: ""
    property string currentVariant: ""
    property int selectedCategory: 0
    property string selectedColorFamily: ""
    property var categoryNames: ["Presets", "Colors", "Fonts", "Wallpaper", "Icons & Cursors"]
    property var categoryIcons: ["󰒓", "󰏘", "󰛖", "󰋩", "󰍽"]

    property var selectedFamilyVariants: {
        let fams = colorFamilies;
        let sel = selectedColorFamily;
        for (let i = 0; i < fams.length; i++)
            if (fams[i].name === sel) return fams[i].variants;
        return [];
    }

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
                familyProc.running = true;
            } catch(e) {}
            buf = "";
        }
    }

    Process {
        id: familyProc; running: false
        command: ["bash", "-c", "jq -r '.family + \"/\" + .variant' /home/kevin/repos/dotfiles/themes/colors/" + (themeState.color_scheme || "gruvbox-dark") + ".json"]
        stdout: SplitParser { onRead: (line) => {
            let p = line.trim().split("/");
            settingsPop.currentFamily = p[0] || "";
            settingsPop.currentVariant = p[1] || "";
            if (settingsPop.selectedColorFamily === "")
                settingsPop.selectedColorFamily = settingsPop.currentFamily;
        } }
    }

    Process {
        id: listColorsProc; running: false
        command: ["bash", "-c", "for f in /home/kevin/repos/dotfiles/themes/colors/*.json; do name=$(basename \"$f\" .json); jq -c --arg name \"$name\" '{schemeName: $name, family: .family, variant: .variant, bg: .colors.bg, fg: .colors.fg, accent: .colors.accent, red: .colors.red, green: .colors.green, blue: .colors.blue, yellow: .colors.yellow, purple: .colors.purple}' \"$f\"; done"]
        property var items: []
        stdout: SplitParser { onRead: (line) => { try { listColorsProc.items.push(JSON.parse(line.trim())); } catch(e) {} } }
        onExited: {
            let schemes = [];
            let families = {};
            let order = [];
            for (let i = 0; i < items.length; i++) {
                let d = items[i];
                schemes.push(d.schemeName);
                let fam = d.family || d.schemeName;
                if (!families[fam]) { families[fam] = { name: fam, variants: [] }; order.push(fam); }
                families[fam].variants.push({
                    schemeName: d.schemeName, variant: d.variant || "dark",
                    bg: d.bg || "#282828", fg: d.fg || "#ebdbb2",
                    accent: d.accent || "#458588", red: d.red || "#cc241d",
                    green: d.green || "#98971a", blue: d.blue || "#458588",
                    yellow: d.yellow || "#d79921", purple: d.purple || "#b16286"
                });
            }
            let result = [];
            for (let j = 0; j < order.length; j++) result.push(families[order[j]]);
            settingsPop.colorSchemes = schemes;
            settingsPop.colorFamilies = result;
            items = [];
        }
    }

    Process {
        id: listPresetsProc; running: false
        command: ["bash", "-c", "for f in /home/kevin/repos/dotfiles/themes/presets/*.json; do basename \"$f\" .json; done"]
        property var items: []
        stdout: SplitParser { onRead: (line) => { listPresetsProc.items.push(line.trim()); } }
        onExited: { settingsPop.presets = items; items = []; }
    }

    Process {
        id: listWallpapersProc; running: false
        command: ["bash", "-c", "ls /home/kevin/repos/dotfiles/wallpapers/ 2>/dev/null || true"]
        property var items: []
        stdout: SplitParser { onRead: (line) => { let t = line.trim(); if (t !== "") listWallpapersProc.items.push(t); } }
        onExited: { settingsPop.wallpapers = items; items = []; }
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
                topLeftRadius: Theme.popupRadius
                bottomLeftRadius: Theme.popupRadius

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2

                    // Header
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36

                        Text {
                            text: "Settings"
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

        // ── Close button (top-right corner) ──
        Rectangle {
            width: 24; height: 24; radius: Theme.hoverRadius; color: "transparent"
            anchors { right: parent.right; top: parent.top; rightMargin: 10; topMargin: 10 }
            z: 1
            Rectangle {
                anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                opacity: closeArea.pressed ? 0.9 : (closeArea.containsMouse ? 0.6 : 0)
                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
            }
            scale: closeArea.pressed ? 0.9 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
            transformOrigin: Item.Center
            Text {
                anchors.centerIn: parent; text: "󰅖"
                color: closeArea.containsMouse ? Theme.redBright : Theme.fg4
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
            }
            MouseArea { id: closeArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.close() }
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
                id: presetsCol; width: parent.width; spacing: 12

                Text { text: "Apply a preset to change multiple settings at once."; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap; Layout.fillWidth: true }

                Flow {
                    Layout.fillWidth: true; spacing: 8
                    Repeater {
                        model: settingsPop.presets
                        delegate: Rectangle {
                            id: presetBtn
                            required property string modelData; required property int index
                            width: presetLabel.implicitWidth + 20; height: 32; radius: Theme.btnRadius
                            color: presetArea.containsMouse ? Theme.bg2 : Theme.bg1
                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                            border.width: 1; border.color: Theme.bg3
                            scale: presetArea.pressed ? 0.95 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center
                            Text { id: presetLabel; anchors.centerIn: parent; text: presetBtn.modelData; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                            MouseArea { id: presetArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runPreset(presetBtn.modelData) }
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
                            property var family: settingsPop.colorFamilies[index]
                            property var preview: family ? family.variants[0] : null
                            property bool isActive: settingsPop.currentFamily === (family ? family.name : "")
                            property bool isSelected: settingsPop.selectedColorFamily === (family ? family.name : "")

                            width: (colorGrid.width - 16) / 3; height: 80
                            radius: Theme.btnRadius + 2
                            color: preview ? preview.bg : Theme.bg1
                            border.width: isSelected ? 2 : 1
                            border.color: isSelected ? Theme.accent : Theme.bg3
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
                                        text: settingsPop.familyDisplayName(famCard.family ? famCard.family.name : "")
                                        color: famCard.preview ? famCard.preview.fg : Theme.fg
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                                        Layout.fillWidth: true
                                    }
                                    Text {
                                        text: "✓"; visible: famCard.isActive
                                        color: famCard.preview ? famCard.preview.accent : Theme.accent
                                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                                    }
                                }

                                Row {
                                    spacing: 4
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.preview ? famCard.preview.accent : Theme.accent; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.preview ? famCard.preview.red : Theme.red; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.preview ? famCard.preview.green : Theme.green; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.preview ? famCard.preview.blue : Theme.blue; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.preview ? famCard.preview.yellow : Theme.yellow; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                    Rectangle { width: 14; height: 14; radius: 7; color: famCard.preview ? famCard.preview.purple : Theme.purple; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                                }
                            }

                            MouseArea {
                                id: famArea; anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: settingsPop.selectedColorFamily = famCard.family.name
                            }
                        }
                    }
                }

                // Variant selector
                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3; visible: settingsPop.selectedColorFamily !== "" }

                ColumnLayout {
                    Layout.fillWidth: true; spacing: 8
                    visible: settingsPop.selectedColorFamily !== ""

                    Text {
                        text: "Variant — " + settingsPop.familyDisplayName(settingsPop.selectedColorFamily)
                        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                    }

                    Flow {
                        Layout.fillWidth: true; spacing: 6
                        Repeater {
                            model: settingsPop.selectedFamilyVariants
                            delegate: Rectangle {
                                id: varBtn
                                required property var modelData; required property int index
                                property string schemeName: modelData.schemeName || ""
                                property string variantName: modelData.variant || ""
                                property bool isCurrent: settingsPop.themeState.color_scheme === schemeName

                                width: varLabel.implicitWidth + 16; height: Theme.btnHeight; radius: Theme.btnRadius
                                color: isCurrent ? Theme.accent : (varArea.containsMouse ? Theme.bg2 : Theme.bg1)
                                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                                Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                                scale: varArea.pressed ? 0.95 : 1.0
                                Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                transformOrigin: Item.Center

                                Text {
                                    id: varLabel; anchors.centerIn: parent
                                    text: varBtn.variantName
                                    color: varBtn.isCurrent ? Theme.bg : Theme.fg
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                }
                                MouseArea {
                                    id: varArea; anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onClicked: settingsPop.runSet("color_scheme", varBtn.schemeName)
                                }
                            }
                        }
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
                    text: "Directory: /home/kevin/repos/dotfiles/wallpapers/"
                    color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    visible: settingsPop.wallpapers.length === 0
                    text: "No wallpapers found. Place image files in /home/kevin/repos/dotfiles/wallpapers/ and they will appear here."
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
                        delegate: Rectangle {
                            id: wpCard
                            required property string modelData; required property int index
                            property bool isCurrent: settingsPop.themeState.wallpaper === "/home/kevin/repos/dotfiles/wallpapers/" + modelData

                            width: (wpGrid.width - 16) / 3
                            height: width * 0.65 + 22
                            radius: Theme.btnRadius
                            color: Theme.bg1
                            border.width: isCurrent ? 2 : 1
                            border.color: isCurrent ? Theme.accent : Theme.bg3
                            Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                            clip: true
                            scale: wpArea.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                            transformOrigin: Item.Center

                            Column {
                                anchors.fill: parent
                                Image {
                                    width: parent.width; height: parent.height - 22
                                    source: "file:///home/kevin/repos/dotfiles/wallpapers/" + wpCard.modelData
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                                Text {
                                    width: parent.width; height: 22
                                    text: wpCard.modelData.replace(/\.\w+$/, "")
                                    color: wpCard.isCurrent ? Theme.accent : Theme.fg3
                                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                    horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
                                    elide: Text.ElideMiddle; leftPadding: 4; rightPadding: 4
                                }
                            }

                            MouseArea { id: wpArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                onClicked: settingsPop.runSet("wallpaper", "/home/kevin/repos/dotfiles/wallpapers/" + wpCard.modelData) }
                        }
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
                        model: ["Adwaita", "Bibata-Modern-Classic", "Bibata-Modern-Ice"]
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
