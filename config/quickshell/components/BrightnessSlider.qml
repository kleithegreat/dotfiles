import QtQuick
import QtQuick.Layouts
import ".." as Root

RowLayout {
    id: root

    property var brightnessDevice: null
    property int valueWidth: Root.Theme.metricValueWidth
    property bool showValue: true

    readonly property string deviceId: brightnessDevice ? (brightnessDevice.device || "") : ""
    readonly property real fraction: brightnessDevice && brightnessDevice.available ? Math.max(0, Math.min(1, Number(brightnessDevice.fraction || 0))) : 0
    readonly property int percent: Math.round(fraction * 100)

    function applyFraction(f) {
        if (deviceId === "")
            return;
        Root.BrightnessService.setBrightnessFractionForDevice(deviceId, f);
    }

    Layout.fillWidth: true
    spacing: 8
    visible: brightnessDevice !== null

    Icon {
        source: root.percent < 25 ? "../icons/brightness-low.svg" : (root.percent < 70 ? "../icons/brightness-medium.svg" : "../icons/brightness-high.svg")
        color: Root.Theme.fg4
        Layout.preferredWidth: Root.Theme.metricIconWidth
    }

    SliderTrack {
        fillColor: Root.Theme.yellowBright
        fraction: root.fraction
        onMoved: (f) => root.applyFraction(f)
    }

    Text {
        visible: root.showValue
        text: root.brightnessDevice && root.brightnessDevice.available ? root.percent + "%" : ""
        color: Root.Theme.fg3
        font.family: Root.Theme.fontFamily
        font.pixelSize: Root.Theme.fontSizeSmall
        Layout.preferredWidth: root.valueWidth
        horizontalAlignment: Text.AlignRight
    }
}
