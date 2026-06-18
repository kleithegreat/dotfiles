import QtQuick
import ".." as Root

Rectangle {
    id: root

    property string text: ""
    property color baseColor: Root.Theme.bg1
    property color hoverColor: Root.Theme.bg2
    property color borderColor: Root.Theme.bg3
    property color textColor: Root.Theme.fg
    property int buttonWidth: 28
    property int fontPixelSize: Root.Theme.fontSize
    property string fontFamily: Root.Theme.fontFamily
    property bool interactive: true

    signal clicked()

    implicitWidth: root.buttonWidth
    implicitHeight: Root.Theme.btnHeight
    width: implicitWidth
    height: implicitHeight
    radius: Root.Theme.btnRadius
    color: stepperArea.containsMouse && root.enabled && root.interactive ? root.hoverColor : root.baseColor
    opacity: root.enabled ? (root.interactive ? 1 : 0.45) : 0.45
    border.width: 1
    border.color: root.borderColor
    Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }

    Text {
        anchors.centerIn: parent
        text: root.text
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
    }

    HoverLayer {
        id: stepperArea
        anchors.fill: parent
        disabled: !root.enabled || !root.interactive
        cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        hoverEnabled: true
        hoverOpacity: 0
        pressedOpacity: 0
        pressedScale: 1.0
        onClicked: root.clicked()
    }
}
