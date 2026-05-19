import QtQuick
import QtQuick.Layouts
import ".." as Root

RowLayout {
    id: root

    property var brightnessDevice: null
    property int valueWidth: Math.max(Root.Theme.fontSize * 3, 32)
    property bool showValue: true

    readonly property string deviceId: brightnessDevice ? (brightnessDevice.device || "") : ""
    readonly property real fraction: brightnessDevice && brightnessDevice.available ? Math.max(0, Math.min(1, Number(brightnessDevice.fraction || 0))) : 0
    readonly property int percent: Math.round(fraction * 100)

    function applyFromX(x, width) {
        if (deviceId === "" || width <= 0)
            return;
        Root.BrightnessService.setBrightnessFractionForDevice(deviceId, x / width);
    }

    Layout.fillWidth: true
    spacing: 8
    visible: brightnessDevice !== null

    Icon {
        source: root.percent < 25 ? "../icons/brightness-low.svg" : (root.percent < 70 ? "../icons/brightness-medium.svg" : "../icons/brightness-high.svg")
        color: Root.Theme.fg4
        Layout.preferredWidth: 16
    }

    Rectangle {
        id: sliderTrack
        Layout.fillWidth: true
        height: Root.Theme.sliderHeight
        radius: Root.Theme.sliderHeight / 2
        color: Root.Theme.bg3

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * root.fraction
            radius: parent.radius
            color: Root.Theme.yellowBright
            Behavior on width {
                Anim {
                    duration: Root.Theme.animMicro
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Root.Theme.animCurveStandard
                }
            }
        }

        Rectangle {
            width: 12
            height: 12
            radius: 6
            color: Root.Theme.fg
            y: (parent.height - height) / 2
            x: Math.max(0, Math.min(parent.width - width, parent.width * root.fraction - width / 2))
            scale: sliderArea.pressed ? 1.2 : (sliderArea.containsMouse ? 1.1 : 1.0)
            Behavior on scale {
                Anim {
                    duration: Root.Theme.animMicro
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Root.Theme.animCurveStandard
                }
            }
            Behavior on x { SpringAnimation { spring: 4; damping: 0.4 } }
        }

        HoverLayer {
            id: sliderArea
            hoverOpacity: 0
            pressedOpacity: 0
            pressedScale: 1.0
            onClicked: (mouse) => { root.applyFromX(mouse.x, sliderTrack.width); }
            onPositionChanged: (mouse) => {
                if (pressed)
                    root.applyFromX(mouse.x, sliderTrack.width);
            }
        }
    }

    Text {
        visible: root.showValue
        text: root.brightnessDevice && root.brightnessDevice.available ? root.percent + "%" : ""
        color: Root.Theme.fg3
        font.family: Root.Theme.systemFamily
        font.pixelSize: Root.Theme.fontSizeSmall
        Layout.preferredWidth: root.valueWidth
        horizontalAlignment: Text.AlignRight
    }
}
