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

    readonly property var monoFontOptions: [
        "JetBrains Mono Nerd Font",
        "Berkeley Mono",
        "Commit Mono",
        "CozetteVector",
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

    readonly property var installedFamilies: {
        let families = Qt.fontFamilies();
        let normalized = {};
        for (let i = 0; i < families.length; i++)
            normalized[families[i].replace(/ /g, "").toLowerCase()] = true;
        return normalized;
    }

    function isFontUnavailable(familyName) {
        return !root.installedFamilies[familyName.replace(/ /g, "").toLowerCase()];
    }

    function monoFontValue(fontName) {
        switch (fontName) {
        case "JetBrains Mono Nerd Font":
            return "JetBrainsMono Nerd Font";
        case "Fira Code Nerd Font":
            return "FiraCode Nerd Font";
        case "Commit Mono":
            return "CommitMono";
        default:
            return fontName;
        }
    }

    function monoFontOptionMatchesCurrent(fontName, currentValue) {
        return root.monoFontValue(fontName) === root.monoFontValue(currentValue);
    }

    function isMonoFontUnavailable(fontName) {
        return root.isFontUnavailable(root.monoFontValue(fontName));
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

    function monoFontLabel(fontName) {
        switch (root.monoFontValue(fontName)) {
        case "JetBrainsMono Nerd Font":
            return "JetBrains Mono";
        case "FiraCode Nerd Font":
            return "Fira Code";
        case "CommitMono":
            return "Commit Mono";
        default:
            return root.monoFontValue(fontName).replace(" Nerd Font", "");
        }
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

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/typography.svg"; color: Theme.fg }
            Text { text: "Fonts"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "CODING FONT"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Components.InlineSelect {
            id: monoFontSelect
            Layout.fillWidth: true
            disabled: root.writePending
            pending: root.isPending("mono_font")
            model: root.monoFontOptions
            currentValue: root.themeState.mono_font
            currentText: root.themeState.mono_font ? root.monoFontLabel(root.themeState.mono_font) : ""
            secondaryText: root.monoFontOptions.length + " fonts"
            textForValue: function(fontName) { return root.monoFontLabel(fontName); }
            matchesCurrent: function(fontName, currentValue) { return root.monoFontOptionMatchesCurrent(fontName, currentValue); }
            isOptionDisabled: function(fontName) { return root.isMonoFontUnavailable(fontName); }
            fontFamily: Theme.systemFamily
            maxVisibleItems: 6
            onExpandedChanged: {
                if (expanded)
                    systemFontSelect.expanded = false;
            }
            onActivated: (fontName) => { root.setRequested("mono_font", root.monoFontValue(fontName)); }
        }

        Row {
            spacing: 8
            opacity: root.isPending("mono_font_size") ? 0.72 : 1
            Behavior on opacity { Components.Anim { duration: Theme.animHover } }

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
                    disabled: root.writePending
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
                    disabled: root.writePending
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
                    opacity: root.isPending(modelData.key) ? 0.72 : 1
                    Behavior on opacity { Components.Anim { duration: Theme.animHover } }

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
                            disabled: root.writePending
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
                            disabled: root.writePending
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.adjustMonoFontSizeOffset(modelData.key, 1)
                        }
                    }

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
            model: root.systemFontOptions
            currentValue: root.themeState.system_font
            currentText: root.themeState.system_font || ""
            secondaryText: root.systemFontOptions.length + " fonts"
            isOptionDisabled: function(fontName) { return root.isFontUnavailable(fontName); }
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
            opacity: root.isPending("font_size") ? 0.72 : 1
            Behavior on opacity { Components.Anim { duration: Theme.animHover } }

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
                    disabled: root.writePending
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: {
                        let s = root.fontBaseSize() - 1;
                        if (s >= 6 && s + root.minimumFontSizeOffset() >= 1)
                            root.setRequested("font_size", String(s));
                    }
                }
            }

            Text { text: String(root.fontBaseSize()); color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize; width: 24; horizontalAlignment: Text.AlignHCenter; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }

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
                    disabled: root.writePending
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    hoverOpacity: 0

                    pressedOpacity: 0

                    pressedScale: 1.0
                    onClicked: {
                        let s = root.fontBaseSize() + 1;
                        if (s <= 24)
                            root.setRequested("font_size", String(s));
                    }
                }
            }
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

                delegate: RowLayout {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: 8
                    opacity: root.isPending(modelData.key) ? 0.72 : 1
                    Behavior on opacity { Components.Anim { duration: Theme.animHover } }

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
                        color: systemOffsetMinus.containsMouse ? Theme.bg2 : Theme.bg1
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                        Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                        Components.HoverLayer {
                            id: systemOffsetMinus
                            anchors.fill: parent
                            disabled: root.writePending
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.adjustFontSizeOffset(modelData.key, -1)
                        }
                    }

                    Text {
                        text: root.formatSignedNumber(root.fontSizeOffset(modelData.key))
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
                        color: systemOffsetPlus.containsMouse ? Theme.bg2 : Theme.bg1
                        border.width: 1
                        border.color: Theme.bg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                        Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize }

                        Components.HoverLayer {
                            id: systemOffsetPlus
                            anchors.fill: parent
                            disabled: root.writePending
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true

                            hoverOpacity: 0

                            pressedOpacity: 0

                            pressedScale: 1.0
                            onClicked: root.adjustFontSizeOffset(modelData.key, 1)
                        }
                    }
                }
            }
        }
    }
}
