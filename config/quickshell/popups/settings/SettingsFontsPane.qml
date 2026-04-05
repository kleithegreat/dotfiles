import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState
    required property var monoFontSizeOffsetTargets

    signal setRequested(string key, string value)

    readonly property var monoFontOptions: [
        "JetBrains Mono Nerd Font",
        "Berkeley Mono",
        "Commit Mono",
        "Recursive Mono",
        "Fira Code Nerd Font",
        "Iosevka Nerd Font"
    ]
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

    function monoFontBaseSize() {
        return root.themeState.mono_font_size || 11;
    }

    function monoFontSizeOffset(key) {
        let value = root.themeState[key];
        return value === undefined || value === null ? 0 : value;
    }

    function effectiveMonoFontSize(key) {
        return monoFontBaseSize() + monoFontSizeOffset(key);
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

    function monoFontLabel(fontName) {
        return fontName.replace(" Nerd Font", "");
    }

    function adjustMonoFontSizeOffset(key, delta) {
        let next = monoFontSizeOffset(key) + delta;
        if (monoFontBaseSize() + next < 1)
            return;

        root.setRequested(key, String(next));
    }

    anchors.fill: parent
    contentHeight: fontsCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: fontsCol
        width: parent.width
        spacing: 16

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/typography.svg"; color: Theme.fg }
            Text { text: "Fonts"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "CODING FONT"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Components.InlineSelect {
            id: monoFontSelect
            Layout.fillWidth: true
            model: root.monoFontOptions
            currentValue: root.themeState.mono_font
            currentText: root.themeState.mono_font ? root.monoFontLabel(root.themeState.mono_font) : ""
            secondaryText: root.monoFontOptions.length + " fonts"
            textForValue: function(fontName) { return root.monoFontLabel(fontName); }
            fontFamily: Theme.systemFamily
            maxVisibleItems: 6
            onExpandedChanged: {
                if (expanded)
                    systemFontSelect.expanded = false;
            }
            onActivated: (fontName) => { root.setRequested("mono_font", fontName); }
        }

        Row {
            spacing: 8

            Text { text: "Size:"; color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }

            Rectangle {
                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: mfMinus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                Components.HoverLayer {
                    id: mfMinus
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: {
                        let s = root.monoFontBaseSize() - 1;
                        if (s >= 6 && s + root.minimumMonoFontSizeOffset() >= 1)
                            root.setRequested("mono_font_size", String(s));
                    }
                }
            }

            Text { text: String(root.monoFontBaseSize()); color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize; width: 24; horizontalAlignment: Text.AlignHCenter; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }

            Rectangle {
                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: mfPlus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                Components.HoverLayer {
                    id: mfPlus
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: {
                        let s = root.monoFontBaseSize() + 1;
                        if (s <= 24)
                            root.setRequested("mono_font_size", String(s));
                    }
                }
            }
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

                delegate: RowLayout {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: modelData.label
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Rectangle {
                        width: 28
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: offsetMinus.containsMouse ? Theme.bg2 : Theme.bg1
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
                            onClicked: root.adjustMonoFontSizeOffset(modelData.key, -1)
                        }
                    }

                    Text {
                        text: root.formatSignedNumber(root.monoFontSizeOffset(modelData.key))
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSize
                        width: 36
                        horizontalAlignment: Text.AlignHCenter
                        height: Theme.btnHeight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Rectangle {
                        width: 28
                        height: Theme.btnHeight
                        radius: Theme.btnRadius
                        color: offsetPlus.containsMouse ? Theme.bg2 : Theme.bg1
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
                            onClicked: root.adjustMonoFontSizeOffset(modelData.key, 1)
                        }
                    }

                    Text {
                        text: "Effective " + String(root.effectiveMonoFontSize(modelData.key))
                        color: Theme.fg4
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "SYSTEM FONT"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Components.InlineSelect {
            id: systemFontSelect
            Layout.fillWidth: true
            model: root.systemFontOptions
            currentValue: root.themeState.system_font
            currentText: root.themeState.system_font || ""
            secondaryText: root.systemFontOptions.length + " fonts"
            fontFamily: Theme.systemFamily
            maxVisibleItems: 7
            onExpandedChanged: {
                if (expanded)
                    monoFontSelect.expanded = false;
            }
            onActivated: (fontName) => { root.setRequested("system_font", fontName); }
        }

        Row {
            spacing: 8

            Text { text: "Size:"; color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }

            Rectangle {
                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: sfMinus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                Components.HoverLayer {
                    id: sfMinus
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: {
                        let s = (root.themeState.font_size || 11) - 1;
                        if (s >= 6)
                            root.setRequested("font_size", String(s));
                    }
                }
            }

            Text { text: String(root.themeState.font_size || 11); color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize; width: 24; horizontalAlignment: Text.AlignHCenter; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }

            Rectangle {
                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: sfPlus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                Components.HoverLayer {
                    id: sfPlus
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: {
                        let s = (root.themeState.font_size || 11) + 1;
                        if (s <= 24)
                            root.setRequested("font_size", String(s));
                    }
                }
            }
        }
    }
}
