import QtQuick
import QtQuick.Layouts
import ".." as Root

RowLayout {
    id: root

    property string label: ""
    property string valueText: ""
    property bool pending: false
    property bool controlsEnabled: true
    property bool decreaseEnabled: true
    property bool increaseEnabled: true
    property int buttonWidth: 28
    property int valueWidth: 36
    property int labelPreferredWidth: 0
    property bool labelFillWidth: true
    property color labelColor: Root.Theme.fg3
    property color valueColor: Root.Theme.fg
    property color baseColor: Root.Theme.bg1
    property color hoverColor: Root.Theme.bg2
    property string labelFontFamily: Root.Theme.fontFamily
    property string valueFontFamily: Root.Theme.fontFamily
    property string buttonFontFamily: Root.Theme.fontFamily
    property int labelPixelSize: Root.Theme.fontSizeSmall
    property int valuePixelSize: Root.Theme.fontSize
    property int buttonPixelSize: Root.Theme.fontSize

    signal decrement()
    signal increment()

    spacing: 8
    opacity: root.pending ? 0.72 : 1
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }

    Text {
        visible: root.label !== ""
        text: root.label
        color: root.labelColor
        font.family: root.labelFontFamily
        font.pixelSize: root.labelPixelSize
        Layout.fillWidth: visible && root.labelFillWidth
        Layout.preferredWidth: visible && root.labelPreferredWidth > 0 ? root.labelPreferredWidth : implicitWidth
        Layout.alignment: Qt.AlignVCenter
        height: Root.Theme.btnHeight
        verticalAlignment: Text.AlignVCenter
    }

    StepperButton {
        buttonWidth: root.buttonWidth
        fontPixelSize: root.buttonPixelSize
        fontFamily: root.buttonFontFamily
        baseColor: root.baseColor
        hoverColor: root.hoverColor
        interactive: root.controlsEnabled && root.decreaseEnabled
        text: "−"
        onClicked: root.decrement()
    }

    Text {
        text: root.valueText
        color: root.valueColor
        font.family: root.valueFontFamily
        font.pixelSize: root.valuePixelSize
        Layout.preferredWidth: root.valueWidth
        horizontalAlignment: Text.AlignHCenter
        height: Root.Theme.btnHeight
        verticalAlignment: Text.AlignVCenter
    }

    StepperButton {
        buttonWidth: root.buttonWidth
        fontPixelSize: root.buttonPixelSize
        fontFamily: root.buttonFontFamily
        baseColor: root.baseColor
        hoverColor: root.hoverColor
        interactive: root.controlsEnabled && root.increaseEnabled
        text: "+"
        onClicked: root.increment()
    }
}
