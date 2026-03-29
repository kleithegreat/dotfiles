import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState
    required property var monoFontSizeOffsetTargets

    signal setRequested(string key, string value)

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

        Text { text: "CODING FONT"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: ["JetBrains Mono Nerd Font", "Berkeley Mono", "Commit Mono", "Recursive Mono", "Fira Code Nerd Font", "Iosevka Nerd Font"]

                delegate: Rectangle {
                    id: mfBtn
                    required property string modelData
                    required property int index
                    property bool isCurrent: root.themeState.mono_font === modelData

                    width: mfLabel.implicitWidth + 16
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: isCurrent ? Theme.accent : (mfArea.containsMouse ? Theme.bg2 : Theme.bg1)
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    border.width: 1
                    border.color: isCurrent ? Theme.accent : Theme.bg3
                    Behavior on border.color { Components.CAnim { duration: Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    scale: mfArea.pressed ? 0.95 : 1.0
                    Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    transformOrigin: Item.Center

                    Text {
                        id: mfLabel
                        anchors.centerIn: parent
                        text: mfBtn.modelData.replace(" Nerd Font", "")
                        color: mfBtn.isCurrent ? Theme.bg : Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    }

                    Components.HoverLayer {
                        id: mfArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.setRequested("mono_font", mfBtn.modelData)
                    }
                }
            }
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

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: ["Overpass", "Inter", "Geist", "IBM Plex Sans", "Rubik", "Noto Sans", "Cantarell", "Source Sans 3", "Outfit", "SF Pro"]

                delegate: Rectangle {
                    id: sfBtn
                    required property string modelData
                    required property int index
                    property bool isCurrent: root.themeState.system_font === modelData

                    width: sfLabel.implicitWidth + 16
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: isCurrent ? Theme.accent : (sfArea.containsMouse ? Theme.bg2 : Theme.bg1)
                    Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    border.width: 1
                    border.color: isCurrent ? Theme.accent : Theme.bg3
                    Behavior on border.color { Components.CAnim { duration: Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    scale: sfArea.pressed ? 0.95 : 1.0
                    Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    transformOrigin: Item.Center

                    Text {
                        id: sfLabel
                        anchors.centerIn: parent
                        text: sfBtn.modelData
                        color: sfBtn.isCurrent ? Theme.bg : Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    }

                    Components.HoverLayer {
                        id: sfArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true

                        hoverOpacity: 0

                        pressedOpacity: 0

                        pressedScale: 1.0
                        onClicked: root.setRequested("system_font", sfBtn.modelData)
                    }
                }
            }
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
