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
    readonly property int brightnessPercent: BrightnessService.brightnessPercent
    readonly property string labelText: BrightnessService.hasBacklight ? (BrightnessService.brightnessAvailable ? brightnessPercent + "%" : "") : DisplayService.nightLightSubtitle

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
                if (!BrightnessService.hasBacklight)
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
            visible: displayRoot.showLabel
            text: displayRoot.labelText
            color: displayArea.containsMouse ? Theme.yellowBright : (BrightnessService.hasBacklight ? Theme.fg : (DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg3))
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
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
