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
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:settings"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    // ── State ──
    property var themeState: ({})
    property var colorSchemes: []
    property var presets: []
    property var wallpapers: []
    property string currentFamily: ""
    property string currentVariant: ""
    property string scriptsDir: ""

    onActiveChanged: { if (active) loadState(); }

    // ── Data loading ──
    function loadState() {
        stateProc.running = true;
        listColorsProc.running = true;
        listPresetsProc.running = true;
        listWallpapersProc.running = true;
        scriptsDirProc.running = true;
    }

    Process {
        id: stateProc; command: ["bash", "-c", "cat ${DOTFILES:-$HOME/dotfiles}/themes/state.json"]; running: false
        property string buf: ""
        stdout: SplitParser { onRead: (line) => { stateProc.buf += line; } }
        onExited: {
            try {
                settingsPop.themeState = JSON.parse(buf);
                // Load family/variant from color scheme
                familyProc.running = true;
            } catch(e) {}
            buf = "";
        }
    }

    // Get scripts dir from DOTFILES env or default
    Process {
        id: scriptsDirProc; command: ["bash", "-c", "echo ${DOTFILES:-$HOME/dotfiles}/scripts"]; running: false
        stdout: SplitParser { onRead: (line) => { settingsPop.scriptsDir = line.trim(); } }
    }

    Process {
        id: familyProc; running: false
        command: ["bash", "-c", "F=${DOTFILES:-$HOME/dotfiles}/themes/colors/" + (themeState.color_scheme || "gruvbox-dark") + ".json; jq -r '.family + \"/\" + .variant' \"$F\""]
        stdout: SplitParser { onRead: (line) => { let p = line.trim().split("/"); settingsPop.currentFamily = p[0] || ""; settingsPop.currentVariant = p[1] || ""; } }
    }

    Process {
        id: listColorsProc; running: false
        command: ["bash", "-c", "for f in ${DOTFILES:-$HOME/dotfiles}/themes/colors/*.json; do echo $(basename $f .json); done"]
        property var items: []
        stdout: SplitParser { onRead: (line) => { listColorsProc.items.push(line.trim()); } }
        onExited: { settingsPop.colorSchemes = items; items = []; }
    }

    Process {
        id: listPresetsProc; running: false
        command: ["bash", "-c", "for f in ${DOTFILES:-$HOME/dotfiles}/themes/presets/*.json; do echo $(basename $f .json); done"]
        property var items: []
        stdout: SplitParser { onRead: (line) => { listPresetsProc.items.push(line.trim()); } }
        onExited: { settingsPop.presets = items; items = []; }
    }

    Process {
        id: listWallpapersProc; running: false
        command: ["bash", "-c", "ls ~/wallpapers/ 2>/dev/null || true"]
        property var items: []
        stdout: SplitParser { onRead: (line) => { let t = line.trim(); if (t !== "") listWallpapersProc.items.push(t); } }
        onExited: { settingsPop.wallpapers = items; items = []; }
    }

    // ── Apply commands ──
    Process { id: applyProc; running: false }

    function runSet(key, value) {
        applyProc.command = ["bash", "-c", scriptsDir + "/set-theme.sh " + key + " '" + value + "'"];
        applyProc.running = true;
        // Reload state after a short delay (configs regenerate)
        reloadTimer.restart();
    }

    function runPreset(name) {
        applyProc.command = ["bash", "-c", scriptsDir + "/set-theme.sh preset " + name];
        applyProc.running = true;
        reloadTimer.restart();
    }

    function runVariant(v) {
        applyProc.command = ["bash", "-c", scriptsDir + "/set-theme.sh variant " + v];
        applyProc.running = true;
        reloadTimer.restart();
    }

    Timer { id: reloadTimer; interval: 1500; onTriggered: loadState() }

    // ── Backdrop ──
    MouseArea {
        anchors.fill: parent
        onClicked: settingsPop.close()
    }

    // ── Panel ──
    Rectangle {
        id: panel
        width: 420; height: parent.height - Theme.popupTopMargin * 2
        anchors { right: parent.right; top: parent.top; margins: Theme.gapOut; topMargin: Theme.popupTopMargin }
        radius: Theme.popupRadius; color: Theme.bg; border.width: 1; border.color: Theme.bg3
        opacity: settingsPop.active ? 1 : 0
        scale: settingsPop.active ? 1.0 : 0.92
        transformOrigin: Item.Top
        Behavior on opacity { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: Theme.animPopupIn; easing.type: Easing.OutCubic } }

        Flickable {
            anchors { fill: parent; margins: Theme.popupPadding }
            contentHeight: col.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: col; width: parent.width; spacing: 16

                // ── Header ──
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "󰃠  Settings"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeLarge; font.bold: true; Layout.fillWidth: true }
                    Text { text: "󰅖"; color: closeArea.containsMouse ? Theme.redBright : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                        MouseArea { id: closeArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.close() } }
                }

                // ── Presets ──
                Text { text: "PRESETS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Flow { Layout.fillWidth: true; spacing: 8
                    Repeater { model: settingsPop.presets
                        Rectangle {
                            required property string modelData; required property int index
                            width: presetLabel.implicitWidth + 20; height: 28; radius: 6
                            color: presetArea.containsMouse ? Theme.bg2 : Theme.bg1; border.width: 1; border.color: Theme.bg3
                            Text { id: presetLabel; anchors.centerIn: parent; text: modelData; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                            MouseArea { id: presetArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runPreset(modelData) }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ── Color Scheme ──
                Text { text: "COLOR SCHEME"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Flow { Layout.fillWidth: true; spacing: 6
                    Repeater { model: settingsPop.colorSchemes
                        Rectangle {
                            required property string modelData; required property int index
                            property bool isCurrent: settingsPop.themeState.color_scheme === modelData
                            width: csLabel.implicitWidth + 16; height: 26; radius: 6
                            color: isCurrent ? Theme.accent : (csArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Text { id: csLabel; anchors.centerIn: parent; text: modelData; color: isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                            MouseArea { id: csArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("color_scheme", modelData) }
                        }
                    }
                }

                // ── Dark / Light Toggle ──
                RowLayout { spacing: 8; Layout.fillWidth: true
                    Text { text: "Variant:"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }
                    Repeater { model: ["dark", "light"]
                        Rectangle {
                            required property string modelData
                            property bool isCurrent: settingsPop.currentVariant === modelData
                            width: varLabel.implicitWidth + 16; height: 26; radius: 6
                            color: isCurrent ? Theme.accent : (varArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Text { id: varLabel; anchors.centerIn: parent; text: modelData; color: isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                            MouseArea { id: varArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runVariant(modelData) }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ── Fonts ──
                Text { text: "FONTS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

                Text { text: "Coding Font"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                Flow { Layout.fillWidth: true; spacing: 6
                    Repeater { model: ["JetBrains Mono Nerd Font", "Berkeley Mono", "Recursive Mono", "Fira Code Nerd Font", "Iosevka Nerd Font"]
                        Rectangle {
                            required property string modelData
                            property bool isCurrent: settingsPop.themeState.coding_font === modelData
                            width: cfLabel.implicitWidth + 14; height: 24; radius: 5
                            color: isCurrent ? Theme.accent : (cfArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Text { id: cfLabel; anchors.centerIn: parent; text: modelData.replace(" Nerd Font", ""); color: isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 10 }
                            MouseArea { id: cfArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("coding_font", modelData) }
                        }
                    }
                }

                Text { text: "System Font"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                Flow { Layout.fillWidth: true; spacing: 6
                    Repeater { model: ["Overpass", "Inter", "Noto Sans", "Cantarell", "Source Sans 3"]
                        Rectangle {
                            required property string modelData
                            property bool isCurrent: settingsPop.themeState.system_font === modelData
                            width: sfLabel.implicitWidth + 14; height: 24; radius: 5
                            color: isCurrent ? Theme.accent : (sfArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Text { id: sfLabel; anchors.centerIn: parent; text: modelData; color: isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 10 }
                            MouseArea { id: sfArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("system_font", modelData) }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ── Wallpaper ──
                Text { text: "WALLPAPER"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Flow { Layout.fillWidth: true; spacing: 6
                    Repeater { model: settingsPop.wallpapers
                        Rectangle {
                            required property string modelData
                            property string fullPath: "~/wallpapers/" + modelData
                            property bool isCurrent: settingsPop.themeState.wallpaper === fullPath
                            width: wpLabel.implicitWidth + 14; height: 24; radius: 5
                            color: isCurrent ? Theme.accent : (wpArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Text { id: wpLabel; anchors.centerIn: parent; text: modelData.replace(/\.\w+$/, ""); color: isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 10; elide: Text.ElideMiddle; width: Math.min(implicitWidth, 120) }
                            MouseArea { id: wpArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("wallpaper", fullPath) }
                        }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

                // ── Icon & Cursor Theme ──
                Text { text: "ICON THEME"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Flow { Layout.fillWidth: true; spacing: 6
                    Repeater { model: ["Papirus-Dark", "Papirus", "Papirus-Light", "Adwaita", "hicolor"]
                        Rectangle {
                            required property string modelData
                            property bool isCurrent: settingsPop.themeState.icon_theme === modelData
                            width: itLabel.implicitWidth + 14; height: 24; radius: 5
                            color: isCurrent ? Theme.accent : (itArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Text { id: itLabel; anchors.centerIn: parent; text: modelData; color: isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 10 }
                            MouseArea { id: itArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("icon_theme", modelData) }
                        }
                    }
                }

                Text { text: "CURSOR THEME"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                Flow { Layout.fillWidth: true; spacing: 6
                    Repeater { model: ["Adwaita", "Bibata-Modern-Classic", "Bibata-Modern-Ice"]
                        Rectangle {
                            required property string modelData
                            property bool isCurrent: settingsPop.themeState.cursor_theme === modelData
                            width: ctLabel.implicitWidth + 14; height: 24; radius: 5
                            color: isCurrent ? Theme.accent : (ctArea.containsMouse ? Theme.bg2 : Theme.bg1)
                            border.width: 1; border.color: isCurrent ? Theme.accent : Theme.bg3
                            Text { id: ctLabel; anchors.centerIn: parent; text: modelData; color: isCurrent ? Theme.bg : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: 10 }
                            MouseArea { id: ctArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: settingsPop.runSet("cursor_theme", modelData) }
                        }
                    }
                }

                // Bottom spacer
                Item { Layout.fillWidth: true; height: 20 }
            }
        }
    }
}
