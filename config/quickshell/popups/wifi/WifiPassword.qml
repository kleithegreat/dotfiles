import qs
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property string targetSsid
    required property string connectError

    signal passwordSubmitted(string password)
    signal backRequested()

    onVisibleChanged: {
        if (visible) { pskInput.text = ""; pskInput.forceActiveFocus(); }
    }

    spacing: 8

    Text { text: "Network: " + root.targetSsid; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

    Rectangle {
        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
        border.width: 1; border.color: pskInput.activeFocus ? Theme.blueBright : Theme.bg3
        Behavior on border.color { ColorAnimation { duration: Theme.animHover } }
        TextInput {
            id: pskInput; anchors.fill: parent; anchors.margins: 8
            color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            echoMode: TextInput.Password; clip: true
            Keys.onReturnPressed: root.passwordSubmitted(text)
            Keys.onEscapePressed: root.backRequested()
        }
        Text { visible: !pskInput.text; text: "Password"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
    }

    Rectangle {
        Layout.fillWidth: true; height: 30; radius: Theme.btnRadius
        color: connPskA.containsMouse ? Theme.blueBright : Theme.bg3
        Behavior on color { ColorAnimation { duration: Theme.animHover } }
        scale: connPskA.pressed ? 0.98 : 1.0
        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
        transformOrigin: Item.Center
        Text { anchors.centerIn: parent; text: "Connect"; color: connPskA.containsMouse ? Theme.bg : Theme.fg
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
        MouseArea { id: connPskA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
            onClicked: root.passwordSubmitted(pskInput.text) }
    }
}
