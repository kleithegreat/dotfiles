import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState
    required property bool writePending
    required property string pendingKey
    required property var fontSizeOffsetTargets
    required property var monoFontSizeOffsetTargets

    signal setRequested(string key, string value)

    function isPending(key) {
        return root.writePending && root.pendingKey === key;
    }

    function monoFontBaseSize() {
        return root.themeState.mono_font_size || 11;
    }

    function fontBaseSize() {
        return root.themeState.font_size || 11;
    }

    function fontSizeOffset(key) {
        let value = root.themeState[key];
        return value === undefined || value === null ? 0 : value;
    }

    function minimumFontSizeOffset() {
        let minOffset = 0;

        for (let i = 0; i < root.fontSizeOffsetTargets.length; i++) {
            let offset = fontSizeOffset(root.fontSizeOffsetTargets[i].key);
            if (offset < minOffset)
                minOffset = offset;
        }

        return minOffset;
    }

    function monoFontSizeOffset(key) {
        let value = root.themeState[key];
        return value === undefined || value === null ? 0 : value;
    }

    function minimumMonoFontSizeOffset() {
        let minOffset = 0;

        for (let i = 0; i < root.monoFontSizeOffsetTargets.length; i++) {
            let offset = monoFontSizeOffset(root.monoFontSizeOffsetTargets[i].key);
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

        root.setRequested(key, String(next));
    }

    function adjustFontSizeOffset(key, delta) {
        let next = fontSizeOffset(key) + delta;
        if (fontBaseSize() + next < 1)
            return;

        root.setRequested(key, String(next));
    }

    anchors.fill: parent
    contentHeight: fontsCol.implicitHeight
    clip: true

    ColumnLayout {
        id: fontsCol
        width: parent.width
        spacing: 16

        Components.SettingsPaneHeader {
            title: "Fonts"
            iconSource: "../icons/typography.svg"
        }

        Text { text: "CODING FONT"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Components.InlineSelect {
            id: monoFontSelect
            Layout.fillWidth: true
            disabled: root.writePending
            pending: root.isPending("mono_font")
            model: ShellOptions.fontPaneMonoFontOptions
            currentValue: root.themeState.mono_font
            currentText: root.themeState.mono_font ? ShellOptions.monoFontLabel(root.themeState.mono_font) : ""
            secondaryText: ShellOptions.fontPaneMonoFontOptions.length + " fonts"
            textForValue: function(fontName) { return ShellOptions.monoFontLabel(fontName); }
            matchesCurrent: function(fontName, currentValue) { return ShellOptions.monoFontOptionMatchesCurrent(fontName, currentValue); }
            isOptionDisabled: function(fontName) { return ShellOptions.isMonoFontUnavailable(fontName); }
            fontFamily: Theme.systemFamily
            maxVisibleItems: 6
            onExpandedChanged: {
                if (expanded)
                    systemFontSelect.expanded = false;
            }
            onActivated: (fontName) => { root.setRequested("mono_font", ShellOptions.monoFontValue(fontName)); }
        }

        Components.ValueStepper {
            opacity: root.isPending("mono_font_size") ? 0.72 : 1
            label: "Size:"
            valueText: String(root.monoFontBaseSize())
            valueWidth: 24
            controlsEnabled: !root.writePending
            decreaseEnabled: root.monoFontBaseSize() > 6 && root.monoFontBaseSize() - 1 + root.minimumMonoFontSizeOffset() >= 1
            increaseEnabled: root.monoFontBaseSize() < 24
            onDecrement: root.setRequested("mono_font_size", String(root.monoFontBaseSize() - 1))
            onIncrement: root.setRequested("mono_font_size", String(root.monoFontBaseSize() + 1))
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Per-target offsets"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: root.monoFontSizeOffsetTargets

                delegate: Components.ValueStepper {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    pending: root.isPending(modelData.key)
                    label: modelData.label
                    labelColor: Theme.fg
                    valueText: root.formatSignedNumber(root.monoFontSizeOffset(modelData.key))
                    valueWidth: 36
                    controlsEnabled: !root.writePending
                    onDecrement: root.adjustMonoFontSizeOffset(modelData.key, -1)
                    onIncrement: root.adjustMonoFontSizeOffset(modelData.key, 1)
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "SYSTEM FONT"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Components.InlineSelect {
            id: systemFontSelect
            Layout.fillWidth: true
            disabled: root.writePending
            pending: root.isPending("system_font")
            model: ShellOptions.systemFontOptions
            currentValue: root.themeState.system_font
            currentText: root.themeState.system_font || ""
            secondaryText: ShellOptions.systemFontOptions.length + " fonts"
            isOptionDisabled: function(fontName) { return ShellOptions.isFontUnavailable(fontName); }
            fontFamily: Theme.systemFamily
            maxVisibleItems: 7
            onExpandedChanged: {
                if (expanded)
                    monoFontSelect.expanded = false;
            }
            onActivated: (fontName) => { root.setRequested("system_font", fontName); }
        }

        Components.ValueStepper {
            opacity: root.isPending("font_size") ? 0.72 : 1
            label: "Size:"
            valueText: String(root.fontBaseSize())
            valueWidth: 24
            controlsEnabled: !root.writePending
            decreaseEnabled: root.fontBaseSize() > 6 && root.fontBaseSize() - 1 + root.minimumFontSizeOffset() >= 1
            increaseEnabled: root.fontBaseSize() < 24
            onDecrement: root.setRequested("font_size", String(root.fontBaseSize() - 1))
            onIncrement: root.setRequested("font_size", String(root.fontBaseSize() + 1))
        }

        ColumnLayout {
            visible: root.fontSizeOffsetTargets.length > 0
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Per-target offsets"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Repeater {
                model: root.fontSizeOffsetTargets

                delegate: Components.ValueStepper {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    pending: root.isPending(modelData.key)
                    label: modelData.label
                    labelColor: Theme.fg
                    valueText: root.formatSignedNumber(root.fontSizeOffset(modelData.key))
                    valueWidth: 36
                    controlsEnabled: !root.writePending
                    onDecrement: root.adjustFontSizeOffset(modelData.key, -1)
                    onIncrement: root.adjustFontSizeOffset(modelData.key, 1)
                }
            }
        }
    }
}
