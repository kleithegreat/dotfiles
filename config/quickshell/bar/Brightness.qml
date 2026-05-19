import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

Item {
    id: displayRoot
    implicitWidth: displayRow.implicitWidth
    implicitHeight: displayRow.implicitHeight
    signal clicked()

    property bool showLabel: true
    readonly property var brightnessDevice: BrightnessService.primaryDeviceForMonitors(DisplayService.monitors, BrightnessService.brightnessDevices)
    readonly property bool hasBrightness: brightnessDevice !== null
    readonly property int brightnessPercent: hasBrightness ? Math.round(Math.max(0, Math.min(1, Number(brightnessDevice.fraction || 0))) * 100) : 0
    readonly property string labelText: hasBrightness ? brightnessPercent + "%" : DisplayService.nightLightSubtitle
    readonly property int labelMaxWidth: Math.max(Theme.fontSize * 6, 84)

    RowLayout {
        id: displayRow
        anchors.fill: parent
        spacing: 4

        Components.StyledIcon {
            id: displayIcon
            animate: true
            swapOpacityOutDuration: 100
            swapScaleOutDuration: 100
            swapOpacityInDuration: 250
            swapScaleInDuration: 300
            source: {
                if (DisplayService.nightLightEnabled)
                    return "../icons/night-light.svg";
                if (!displayRoot.hasBrightness)
                    return "../icons/monitor.svg";
                if (displayRoot.brightnessPercent < 25)
                    return "../icons/brightness-low.svg";
                if (displayRoot.brightnessPercent < 60)
                    return "../icons/brightness-medium.svg";
                if (displayRoot.brightnessPercent < 85)
                    return "../icons/brightness-high.svg";
                return "../icons/brightness-max.svg";
            }
            color: displayArea.containsMouse ? Theme.yellowBright : (DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg)
            Behavior on color { Components.CAnim { duration: Theme.animHover } }
        }

        Text {
            id: brightnessLabel
            visible: displayRoot.showLabel
            text: displayRoot.labelText
            color: displayArea.containsMouse ? Theme.yellowBright : (displayRoot.hasBrightness ? Theme.fg : (DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg3))
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            Layout.preferredWidth: Math.min(brightnessLabel.implicitWidth, displayRoot.labelMaxWidth)
            Layout.maximumWidth: displayRoot.labelMaxWidth
            Behavior on color { Components.CAnim { duration: Theme.animHover } }
        }
    }

    MouseArea {
        id: displayArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: displayRoot.clicked()
    }
}
