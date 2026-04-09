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

    readonly property var cursorThemeOptions: [
        "Adwaita",
        "BreezeX-RosePine-Linux",
        "BreezeX-RosePineDawn-Linux",
        "Bibata-Modern-Classic",
        "Bibata-Modern-Ice",
        "Bibata-Original-Classic",
        "Bibata-Original-Ice"
    ]

    readonly property var accelProfileOptions: [
        "adaptive",
        "flat"
    ]

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

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Components.Icon { source: "../icons/cursor.svg"; color: Theme.fg }

            Text {
                text: "Mouse"
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.headerFontSize
                font.bold: true
                Layout.fillWidth: true
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text {
            visible: root.mouseRuntimeError !== ""
            text: root.mouseRuntimeError
            color: Theme.redBright
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Text {
            text: "CURSOR"
            color: Theme.fg4
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Cursor Theme"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: Math.max(Theme.fontSize * 8, 104)
            }

            Components.InlineSelect {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                disabled: root.themeWritePending
                pending: root.isThemePending("cursor_theme")
                model: root.cursorThemeOptions
                currentValue: root.themeState.cursor_theme
                currentText: root.themeState.cursor_theme || ""
                secondaryText: root.cursorThemeOptions.length + " themes"
                fontFamily: Theme.systemFamily
                maxVisibleItems: 7
                onActivated: (value) => root.themeSetRequested("cursor_theme", value)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Cursor Size"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Rectangle {
                id: cursorSizeMinusButton
                property bool canDecrease: (root.themeState.cursor_size || 24) > 16

                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                opacity: root.isThemePending("cursor_size") ? 0.72 : (canDecrease ? 1 : 0.45)
                color: cursorSizeMinus.containsMouse && canDecrease ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text {
                    anchors.centerIn: parent
                    text: "-"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Components.HoverLayer {
                    id: cursorSizeMinus
                    disabled: root.themeWritePending || !cursorSizeMinusButton.canDecrease
                    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.themeSetRequested("cursor_size", String((root.themeState.cursor_size || 24) - 4))
                }
            }

            Text {
                text: String(root.themeState.cursor_size || 24)
                opacity: root.isThemePending("cursor_size") ? 0.72 : 1
                color: Theme.fg
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSize
                width: 36
                horizontalAlignment: Text.AlignHCenter
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }
            }

            Rectangle {
                id: cursorSizePlusButton
                property bool canIncrease: (root.themeState.cursor_size || 24) < 48

                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                opacity: root.isThemePending("cursor_size") ? 0.72 : (canIncrease ? 1 : 0.45)
                color: cursorSizePlus.containsMouse && canIncrease ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Components.HoverLayer {
                    id: cursorSizePlus
                    disabled: root.themeWritePending || !cursorSizePlusButton.canIncrease
                    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.themeSetRequested("cursor_size", String((root.themeState.cursor_size || 24) + 4))
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text {
            text: "POINTER"
            color: Theme.fg4
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Mouse Speed"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Rectangle {
                id: sensitivityMinusButton
                property real currentValue: root.mouseNumber("sensitivity", 0.75)
                property bool canDecrease: currentValue > -1.0

                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                opacity: root.isMousePending("sensitivity") ? 0.72 : (canDecrease ? 1 : 0.45)
                color: sensitivityMinus.containsMouse && canDecrease ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text {
                    anchors.centerIn: parent
                    text: "-"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Components.HoverLayer {
                    id: sensitivityMinus
                    disabled: root.mouseWritePending || !sensitivityMinusButton.canDecrease
                    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.adjustMouseValue("sensitivity", 0.75, -0.05, -1.0, 1.0)
                }
            }

            Text {
                text: root.formatDecimal(root.mouseNumber("sensitivity", 0.75))
                opacity: root.isMousePending("sensitivity") ? 0.72 : 1
                color: Theme.fg
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSize
                width: 52
                horizontalAlignment: Text.AlignHCenter
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }
            }

            Rectangle {
                id: sensitivityPlusButton
                property real currentValue: root.mouseNumber("sensitivity", 0.75)
                property bool canIncrease: currentValue < 1.0

                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                opacity: root.isMousePending("sensitivity") ? 0.72 : (canIncrease ? 1 : 0.45)
                color: sensitivityPlus.containsMouse && canIncrease ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Components.HoverLayer {
                    id: sensitivityPlus
                    disabled: root.mouseWritePending || !sensitivityPlusButton.canIncrease
                    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.adjustMouseValue("sensitivity", 0.75, 0.05, -1.0, 1.0)
                }
            }
        }

        Text {
            text: "Applies to the shared Hyprland default. Device-specific overrides can still replace it."
            color: Theme.fg4
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall - 1
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Acceleration"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: Math.max(Theme.fontSize * 8, 104)
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
                fontFamily: Theme.systemFamily
                maxVisibleItems: 4
                onActivated: (value) => root.mouseSetRequested("accel_profile", value)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Scroll Speed"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Rectangle {
                id: scrollFactorMinusButton
                property real currentValue: root.mouseNumber("scroll_factor", 1.0)
                property bool canDecrease: currentValue > 0.25

                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                opacity: root.isMousePending("scroll_factor") ? 0.72 : (canDecrease ? 1 : 0.45)
                color: scrollFactorMinus.containsMouse && canDecrease ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text {
                    anchors.centerIn: parent
                    text: "-"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Components.HoverLayer {
                    id: scrollFactorMinus
                    disabled: root.mouseWritePending || !scrollFactorMinusButton.canDecrease
                    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.adjustMouseValue("scroll_factor", 1.0, -0.25, 0.25, 5.0)
                }
            }

            Text {
                text: root.formatDecimal(root.mouseNumber("scroll_factor", 1.0))
                opacity: root.isMousePending("scroll_factor") ? 0.72 : 1
                color: Theme.fg
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSize
                width: 52
                horizontalAlignment: Text.AlignHCenter
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }
            }

            Rectangle {
                id: scrollFactorPlusButton
                property real currentValue: root.mouseNumber("scroll_factor", 1.0)
                property bool canIncrease: currentValue < 5.0

                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                opacity: root.isMousePending("scroll_factor") ? 0.72 : (canIncrease ? 1 : 0.45)
                color: scrollFactorPlus.containsMouse && canIncrease ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text {
                    anchors.centerIn: parent
                    text: "+"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Components.HoverLayer {
                    id: scrollFactorPlus
                    disabled: root.mouseWritePending || !scrollFactorPlusButton.canIncrease
                    cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.adjustMouseValue("scroll_factor", 1.0, 0.25, 0.25, 5.0)
                }
            }
        }
    }
}
