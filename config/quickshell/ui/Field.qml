import QtQuick
import qs

Rectangle {
    id: root

    property alias text: input.text
    property alias placeholder: hint.text
    property alias echo: input.echoMode
    property alias focused: input.activeFocus

    signal accepted

    implicitHeight: Metrics.controlHeight + Metrics.s1
    implicitWidth: 200
    radius: Metrics.rControl
    color: Theme.fillTrack
    border.width: Metrics.hairline
    border.color: input.activeFocus ? Theme.accent : "transparent"
    antialiasing: true

    Behavior on border.color {
        Tint {}
    }

    function claim() {
        input.forceActiveFocus();
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Metrics.s3
        anchors.rightMargin: Metrics.s3
        verticalAlignment: TextInput.AlignVCenter
        font.family: Theme.family
        font.pixelSize: Theme.sizeCallout
        color: Theme.text
        selectionColor: Theme.accent
        selectedTextColor: Theme.onAccent
        selectByMouse: true
        clip: true
        onAccepted: root.accepted()
    }

    Label {
        id: hint
        anchors.left: input.left
        anchors.verticalCenter: parent.verticalCenter
        role: "callout"
        color: Theme.textQuaternary
        visible: input.text === ""
    }
}
