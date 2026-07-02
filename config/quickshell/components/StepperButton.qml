import QtQuick
import ".." as Root

Rectangle {
    id: root

    property string text: ""
    property color baseColor: Root.Theme.bg1
    property color hoverColor: Root.Theme.bg2
    property int buttonWidth: 28
    property int fontPixelSize: Root.Theme.fontSize
    property string fontFamily: Root.Theme.fontFamily
    property bool interactive: true

    signal clicked()

    implicitWidth: root.buttonWidth
    implicitHeight: Root.Theme.btnHeight
    radius: Root.Theme.btnRadius
    color: stepperArea.containsMouse && root.enabled && root.interactive ? root.hoverColor : root.baseColor
    opacity: root.enabled && root.interactive ? 1 : 0.45
    border.width: 1
    border.color: Root.Theme.bg3
    Behavior on color { StdCAnim { duration: Root.Theme.animHover } }
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }

    Text {
        anchors.centerIn: parent
        text: root.text
        color: Root.Theme.fg
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
    }

    HoverLayer {
        id: stepperArea
        disabled: !root.enabled || !root.interactive
        flat: true
        onClicked: root.clicked()
    }
}
