import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

ColumnLayout {
    id: root
    required property var colorFamilies
    required property var themeState
    required property bool writePending
    required property string pendingKey

    signal colorSchemeSelected(string schemeName)
    signal darkHintSelected(string value)

    function isPending(key) {
        return root.writePending && root.pendingKey === key;
    }

    function familyDisplayName(name) {
        if (name === "tokyonight")
            return "Tokyo Night";
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    function colorSchemeLabel(option) {
        if (!option)
            return "";

        return root.familyDisplayName(option.family) + " " + option.variant;
    }

    function currentColorSchemeLabel() {
        for (let i = 0; i < root.colorFamilies.length; i++) {
            let option = root.colorFamilies[i];
            if (option && option.schemeName === root.themeState.color_scheme)
                return root.colorSchemeLabel(option);
        }

        return "";
    }

    anchors.fill: parent
    spacing: 16

    RowLayout { Layout.fillWidth: true; spacing: 8
        Components.Icon { source: "../icons/palette.svg"; color: Theme.fg }
        Text { text: "Colors"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        Text {
            text: "COLOR SCHEME"
            color: Theme.fg4
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Components.InlineSelect {
            id: colorSchemeSelect
            Layout.fillWidth: true
            disabled: root.writePending
            pending: root.isPending("color_scheme")
            model: root.colorFamilies
            currentValue: root.themeState.color_scheme
            currentText: root.currentColorSchemeLabel()
            secondaryText: root.colorFamilies.length + " schemes"
            fontFamily: Theme.systemFamily
            maxVisibleItems: 7
            textForValue: function(option) { return root.colorSchemeLabel(option); }
            matchesCurrent: function(option, currentValue) { return option && option.schemeName === currentValue; }
            onActivated: (option) => root.colorSchemeSelected(option.schemeName)
        }
    }

    Rectangle {
        Layout.fillWidth: true
        height: 1
        color: Theme.bg3
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            opacity: root.isPending("dark_hint") ? 0.72 : 1
            Behavior on opacity { Components.Anim { duration: Theme.animHover } }

            Text {
                text: root.themeState.dark_hint === false ? "Prefer light browser theme" : "Prefer dark browser theme"
                color: Theme.fg
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Text {
                text: root.themeState.dark_hint === false ? "Light" : "Dark"
                color: root.themeState.dark_hint === false ? Theme.fg4 : Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Components.ToggleSwitch {
                checked: root.themeState.dark_hint !== false
                disabled: root.writePending
                pending: root.isPending("dark_hint")
                onToggled: root.darkHintSelected(root.themeState.dark_hint === false ? "dark" : "light")
            }
        }
    }
}
