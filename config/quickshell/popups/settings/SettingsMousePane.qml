import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState
    required property bool themeWritePending
    required property string pendingThemeKey
    required property var mouseSettings
    required property string mouseRuntimeError
    required property bool mouseWritePending
    required property string pendingMouseKey

    readonly property var accelProfileOptions: [
        "adaptive",
        "flat"
    ]

    readonly property int rowLabelWidth: Math.max(Theme.fontSize * 8, 104)

    signal themeSetRequested(string key, string value)
    signal mouseSetRequested(string key, string value)

    function isThemePending(key) {
        return root.themeWritePending && root.pendingThemeKey === key;
    }

    function isMousePending(key) {
        return root.mouseWritePending && root.pendingMouseKey === key;
    }

    function mouseNumber(key, fallback) {
        let parsed = Number(root.mouseSettings[key]);
        return isNaN(parsed) ? fallback : parsed;
    }

    function formatDecimal(value) {
        let rounded = Math.round(value * 100) / 100;
        let text = rounded.toFixed(2);

        while (text.length > 3 && text.endsWith("0"))
            text = text.slice(0, text.length - 1);

        if (text.endsWith("."))
            text += "0";

        return text;
    }

    function adjustMouseValue(key, fallback, delta, minimum, maximum) {
        let next = Math.round((root.mouseNumber(key, fallback) + delta) * 100) / 100;
        if (next < minimum || next > maximum)
            return;

        root.mouseSetRequested(key, root.formatDecimal(next));
    }

    anchors.fill: parent
    contentHeight: mouseCol.implicitHeight
    clip: true

    ColumnLayout {
        id: mouseCol
        width: parent.width
        spacing: 16

        Components.SettingsPaneHeader {
            title: "Mouse"
            iconSource: "../icons/cursor.svg"
        }

        Text {
            visible: root.mouseRuntimeError !== ""
            text: root.mouseRuntimeError
            color: Theme.redBright
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Components.SectionLabel {
            text: "CURSOR"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Cursor Theme"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: root.rowLabelWidth
            }

            Components.InlineSelect {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                disabled: root.themeWritePending
                pending: root.isThemePending("cursor_theme")
                model: ShellOptions.cursorThemeOptions
                currentValue: root.themeState.cursor_theme
                currentText: root.themeState.cursor_theme || ""
                secondaryText: ShellOptions.cursorThemeOptions.length + " themes"
                fontFamily: Theme.fontFamily
                maxVisibleItems: 7
                onActivated: (value) => root.themeSetRequested("cursor_theme", value)
            }
        }

        Components.ValueStepper {
            Layout.fillWidth: true
            pending: root.isThemePending("cursor_size")
            label: "Cursor Size"
            valueText: String(root.themeState.cursor_size || 24)
            valueWidth: 36
            controlsEnabled: !root.themeWritePending
            decreaseEnabled: (root.themeState.cursor_size || 24) > 16
            increaseEnabled: (root.themeState.cursor_size || 24) < 48
            onDecrement: root.themeSetRequested("cursor_size", String((root.themeState.cursor_size || 24) - 4))
            onIncrement: root.themeSetRequested("cursor_size", String((root.themeState.cursor_size || 24) + 4))
        }

        Components.Divider {}

        Components.SectionLabel {
            text: "POINTER"
        }

        Components.ValueStepper {
            Layout.fillWidth: true
            pending: root.isMousePending("sensitivity")
            label: "Mouse Speed"
            valueText: root.formatDecimal(root.mouseNumber("sensitivity", 0.75))
            valueWidth: 52
            controlsEnabled: !root.mouseWritePending
            decreaseEnabled: root.mouseNumber("sensitivity", 0.75) > -1.0
            increaseEnabled: root.mouseNumber("sensitivity", 0.75) < 1.0
            onDecrement: root.adjustMouseValue("sensitivity", 0.75, -0.05, -1.0, 1.0)
            onIncrement: root.adjustMouseValue("sensitivity", 0.75, 0.05, -1.0, 1.0)
        }

        Text {
            text: "Applies to the shared Hyprland default. Device-specific overrides can still replace it."
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeMini
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Acceleration"
                color: Theme.fg3
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: root.rowLabelWidth
            }

            Components.InlineSelect {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                disabled: root.mouseWritePending
                pending: root.isMousePending("accel_profile")
                model: root.accelProfileOptions
                currentValue: root.mouseSettings.accel_profile || "flat"
                currentText: root.mouseSettings.accel_profile || "flat"
                secondaryText: "libinput profile"
                fontFamily: Theme.fontFamily
                maxVisibleItems: 4
                onActivated: (value) => root.mouseSetRequested("accel_profile", value)
            }
        }

        Components.ValueStepper {
            Layout.fillWidth: true
            pending: root.isMousePending("scroll_factor")
            label: "Scroll Speed"
            valueText: root.formatDecimal(root.mouseNumber("scroll_factor", 1.0))
            valueWidth: 52
            controlsEnabled: !root.mouseWritePending
            decreaseEnabled: root.mouseNumber("scroll_factor", 1.0) > 0.25
            increaseEnabled: root.mouseNumber("scroll_factor", 1.0) < 5.0
            onDecrement: root.adjustMouseValue("scroll_factor", 1.0, -0.25, 0.25, 5.0)
            onIncrement: root.adjustMouseValue("scroll_factor", 1.0, 0.25, 0.25, 5.0)
        }
    }
}
