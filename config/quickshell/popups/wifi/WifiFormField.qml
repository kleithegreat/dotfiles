import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

// Bordered text-field scaffold shared by WifiPassword and WifiEnterprise:
// focus/error border, placeholder, clear button, optional Show/Hide reveal,
// and the error message below the field.
ColumnLayout {
    id: root

    required property string placeholder
    property string errorText: ""
    property bool isPassword: false
    property bool revealed: false
    property alias text: input.text

    signal submitted()
    signal escaped()
    signal edited()
    signal revealToggled()

    function forceInputFocus() { input.forceActiveFocus(); }

    spacing: 8

    Rectangle {
        Layout.fillWidth: true; height: 36; radius: Theme.btnRadius; color: Theme.bg2
        border.width: 1
        border.color: root.errorText !== ""
            ? Theme.redBright
            : (input.activeFocus ? Theme.blueBright : Theme.bg3)
        Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

        Row {
            id: fieldActions
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                visible: root.isPassword
                width: revealLabel.implicitWidth + 10
                height: 22
                radius: Theme.hoverRadius
                color: revealArea.containsMouse ? Theme.bg3 : "transparent"
                border.width: 1
                border.color: revealArea.containsMouse ? Theme.bg3 : "transparent"
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

                Text {
                    id: revealLabel
                    anchors.centerIn: parent
                    text: root.revealed ? "Hide" : "Show"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMini
                }

                Components.HoverLayer {
                    id: revealArea
                    flat: true
                    onClicked: {
                        root.revealToggled();
                        input.forceActiveFocus();
                    }
                }
            }

            Rectangle {
                visible: input.text !== ""
                width: 22
                height: 22
                radius: Theme.hoverRadius
                color: clearArea.containsMouse ? Theme.bg3 : "transparent"
                border.width: 1
                border.color: clearArea.containsMouse ? Theme.bg3 : "transparent"
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

                Components.Icon {
                    anchors.centerIn: parent
                    source: "../../icons/close.svg"
                    color: Theme.fg4
                    iconSize: Theme.fontSizeSmall
                }

                Components.HoverLayer {
                    id: clearArea
                    flat: true
                    onClicked: {
                        input.text = "";
                        root.edited();
                        input.forceActiveFocus();
                    }
                }
            }
        }

        TextInput {
            id: input
            anchors.left: parent.left
            anchors.right: fieldActions.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            echoMode: root.isPassword && !root.revealed ? TextInput.Password : TextInput.Normal
            clip: true
            onTextEdited: root.edited()
            Keys.onReturnPressed: root.submitted()
            Keys.onEscapePressed: root.escaped()
        }
        Text { visible: !input.text; text: root.placeholder; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
    }

    Text {
        visible: root.errorText !== ""
        text: root.errorText
        color: Theme.redBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMini
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }
}
