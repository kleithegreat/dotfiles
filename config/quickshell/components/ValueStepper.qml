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
    property int valueWidth: 36
    property color labelColor: Root.Theme.fg3
    property color baseColor: Root.Theme.bg1
    property string labelFontFamily: Root.Theme.fontFamily
    property string valueFontFamily: Root.Theme.fontFamily
    property string buttonFontFamily: Root.Theme.fontFamily

    signal decrement()
    signal increment()

    spacing: 8
    opacity: root.pending ? Root.Theme.pendingOpacity : 1
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }

    Text {
        visible: root.label !== ""
        text: root.label
        color: root.labelColor
        font.family: root.labelFontFamily
        font.pixelSize: Root.Theme.fontSizeSmall
        Layout.fillWidth: visible
        Layout.alignment: Qt.AlignVCenter
        height: Root.Theme.btnHeight
        verticalAlignment: Text.AlignVCenter
    }

    StepperButton {
        fontFamily: root.buttonFontFamily
        baseColor: root.baseColor
        interactive: root.controlsEnabled && root.decreaseEnabled
        text: "−"
        onClicked: root.decrement()
    }

    Text {
        text: root.valueText
        color: Root.Theme.fg
        font.family: root.valueFontFamily
        font.pixelSize: Root.Theme.fontSize
        Layout.preferredWidth: root.valueWidth
        horizontalAlignment: Text.AlignHCenter
        height: Root.Theme.btnHeight
        verticalAlignment: Text.AlignVCenter
    }

    StepperButton {
        fontFamily: root.buttonFontFamily
        baseColor: root.baseColor
        interactive: root.controlsEnabled && root.increaseEnabled
        text: "+"
        onClicked: root.increment()
    }
}
