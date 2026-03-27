import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Flickable {
    id: root
    required property string hyprRuntimeError
    required property var hyprOptionInfo
    required property var hyprGeneralOptions
    required property var hyprDecorationOptions
    required property var hyprBlurOptions
    required property var hyprDraftState
    required property var themeState

    signal hyprOptionToggled(string option)
    signal hyprOptionAdjusted(string option, int direction)

    function hyprOptionMeta(option) {
        return root.hyprOptionInfo[option] || ({});
    }

    function hyprStateKey(option) {
        return root.hyprOptionMeta(option).stateKey || "";
    }

    function hyprThemeStateValue(stateKey, fallback) {
        let value = root.themeState[stateKey];
        return value === undefined || value === null ? fallback : value;
    }

    function hyprStateValue(stateKey, fallback) {
        let value = root.hyprDraftState[stateKey];
        if (value !== undefined && value !== null)
            return value;

        return root.hyprThemeStateValue(stateKey, fallback);
    }

    function hyprIntValue(option) {
        let meta = root.hyprOptionMeta(option);
        let value = root.hyprStateValue(root.hyprStateKey(option), meta.fallback);
        let parsed = parseInt(value, 10);

        return isNaN(parsed) ? (meta.fallback === undefined ? 0 : meta.fallback) : parsed;
    }

    function hyprBoolValue(option) {
        let meta = root.hyprOptionMeta(option);
        let value = root.hyprStateValue(root.hyprStateKey(option), meta.fallback);
        return value === undefined ? !!meta.fallback : !!value;
    }

    anchors.fill: parent
    contentHeight: hyprCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: hyprCol
        width: parent.width
        spacing: 16

        Text {
            visible: root.hyprRuntimeError !== ""
            text: root.hyprRuntimeError
            color: Theme.redBright
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Text {
            text: "GENERAL"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Repeater {
            model: root.hyprGeneralOptions

            delegate: RowLayout {
                required property string modelData
                required property int index
                property var meta: root.hyprOptionMeta(modelData)

                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: meta.label
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    id: hyprMinusBtn
                    property bool canDecrease: meta.minimum === undefined || root.hyprIntValue(modelData) > meta.minimum

                    Layout.preferredWidth: 28
                    Layout.preferredHeight: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: hyprMinusArea.containsMouse && canDecrease ? Theme.bg2 : Theme.bg1
                    opacity: canDecrease ? 1 : 0.45
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }

                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        id: hyprMinusArea
                        anchors.fill: parent
                        enabled: hyprMinusBtn.canDecrease
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        onClicked: root.hyprOptionAdjusted(modelData, -1)
                    }
                }

                Text {
                    text: String(root.hyprIntValue(modelData))
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    id: hyprPlusBtn
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: hyprPlusArea.containsMouse ? Theme.bg2 : Theme.bg1
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        id: hyprPlusArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.hyprOptionAdjusted(modelData, 1)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text {
            text: "DECORATION"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Repeater {
            model: root.hyprDecorationOptions

            delegate: RowLayout {
                required property string modelData
                required property int index
                property var meta: root.hyprOptionMeta(modelData)

                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: meta.label
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    id: decorationMinusBtn
                    property bool canDecrease: meta.minimum === undefined || root.hyprIntValue(modelData) > meta.minimum

                    Layout.preferredWidth: 28
                    Layout.preferredHeight: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: decorationMinusArea.containsMouse && canDecrease ? Theme.bg2 : Theme.bg1
                    opacity: canDecrease ? 1 : 0.45
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }

                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        id: decorationMinusArea
                        anchors.fill: parent
                        enabled: decorationMinusBtn.canDecrease
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        onClicked: root.hyprOptionAdjusted(modelData, -1)
                    }
                }

                Text {
                    text: String(root.hyprIntValue(modelData))
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    id: decorationPlusBtn
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: decorationPlusArea.containsMouse ? Theme.bg2 : Theme.bg1
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        id: decorationPlusArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.hyprOptionAdjusted(modelData, 1)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text {
            text: "BLUR"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.hyprOptionMeta("decoration:blur:enabled").label
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: root.hyprBoolValue("decoration:blur:enabled") ? "On" : "Off"
                color: root.hyprBoolValue("decoration:blur:enabled") ? Theme.fg3 : Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignVCenter
            }

            Components.ToggleSwitch {
                checked: root.hyprBoolValue("decoration:blur:enabled")
                onToggled: root.hyprOptionToggled("decoration:blur:enabled")
            }
        }

        Repeater {
            model: root.hyprBlurOptions

            delegate: RowLayout {
                required property string modelData
                required property int index
                property var meta: root.hyprOptionMeta(modelData)

                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: meta.label
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    id: blurMinusBtn
                    property bool canDecrease: meta.minimum === undefined || root.hyprIntValue(modelData) > meta.minimum

                    Layout.preferredWidth: 28
                    Layout.preferredHeight: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: blurMinusArea.containsMouse && canDecrease ? Theme.bg2 : Theme.bg1
                    opacity: canDecrease ? 1 : 0.45
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }

                    Text {
                        anchors.centerIn: parent
                        text: "−"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        id: blurMinusArea
                        anchors.fill: parent
                        enabled: blurMinusBtn.canDecrease
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        onClicked: root.hyprOptionAdjusted(modelData, -1)
                    }
                }

                Text {
                    text: String(root.hyprIntValue(modelData))
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    Layout.preferredWidth: 36
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                Rectangle {
                    id: blurPlusBtn
                    Layout.preferredWidth: 28
                    Layout.preferredHeight: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: blurPlusArea.containsMouse ? Theme.bg2 : Theme.bg1
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    MouseArea {
                        id: blurPlusArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.hyprOptionAdjusted(modelData, 1)
                    }
                }
            }
        }

        Text {
            text: "Blur size and passes must stay at 1 or above."
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text {
            text: "ANIMATIONS"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: root.hyprOptionMeta("animations:enabled").label
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: root.hyprBoolValue("animations:enabled") ? "On" : "Off"
                color: root.hyprBoolValue("animations:enabled") ? Theme.fg3 : Theme.fg4
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignVCenter
            }

            Components.ToggleSwitch {
                checked: root.hyprBoolValue("animations:enabled")
                onToggled: root.hyprOptionToggled("animations:enabled")
            }
        }
    }
}
