import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

// Primary submit button shared by WifiPassword and WifiEnterprise.
Rectangle {
    id: root

    required property string label
    property bool canSubmit: false

    signal clicked()

    Layout.fillWidth: true
    height: 30; radius: Theme.btnRadius
    color: root.canSubmit ? (submitArea.containsMouse ? Theme.blueBright : Theme.bg3) : Theme.bg2
    opacity: root.canSubmit ? 1 : 0.6
    Behavior on color { Components.StdCAnim { duration: Theme.animHover } }

    Components.HoverLayer {
        id: submitArea
        disabled: !root.canSubmit
        hoverOpacity: 0
        pressedOpacity: 0
        onClicked: root.clicked()

        Text { anchors.centerIn: parent; text: root.label; color: root.canSubmit ? (submitArea.containsMouse ? Theme.bg : Theme.fg) : Theme.fg4
            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
    }
}
