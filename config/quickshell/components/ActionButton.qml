import QtQuick
import ".." as Root

Rectangle {
    id: root

    property alias text: label.text
    property color baseColor: Root.Theme.bg1
    property color hoverColor: Root.Theme.bg2
    property color borderColor: Root.Theme.bg3
    property color textColor: Root.Theme.fg
    property real disabledOpacity: 0.45
    property int fixedWidth: 0
    property int paddingH: Root.Theme.btnPaddingH
    property int fontPixelSize: Root.Theme.fontSizeSmall
    property string fontFamily: Root.Theme.fontFamily
    property bool fontBold: false

    signal clicked()

    implicitWidth: root.fixedWidth > 0 ? root.fixedWidth : label.implicitWidth + root.paddingH * 2
    implicitHeight: Root.Theme.btnHeight
    width: implicitWidth
    height: implicitHeight
    radius: Root.Theme.btnRadius
    color: buttonArea.containsMouse && root.enabled ? root.hoverColor : root.baseColor
    opacity: root.enabled ? 1 : root.disabledOpacity
    border.width: 1
    border.color: root.borderColor
    Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
    Behavior on border.color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }
    scale: buttonArea.pressed && root.enabled ? 0.95 : 1.0
    Behavior on scale { Anim { duration: Root.Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
    transformOrigin: Item.Center

    Text {
        id: label
        anchors.centerIn: parent
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: root.fontPixelSize
        font.bold: root.fontBold
        Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
    }

    HoverLayer {
        id: buttonArea
        anchors.fill: parent
        disabled: !root.enabled
        cursorShape: disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
        hoverEnabled: true
        hoverOpacity: 0
        pressedOpacity: 0
        pressedScale: 1.0
        onClicked: root.clicked()
    }
}
