import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

Item {
    id: displayRoot
    implicitWidth: displayRow.implicitWidth
    implicitHeight: displayRow.implicitHeight
    signal clicked()

    readonly property int brightnessPercent: DisplayService.brightnessPercent
    readonly property string labelText: DisplayService.hasBacklight ? (DisplayService.brightnessAvailable ? brightnessPercent + "%" : "") : DisplayService.nightLightSubtitle

    RowLayout {
        id: displayRow
        anchors.fill: parent
        spacing: 4

        Components.StyledText {
            id: displayIcon
            animate: true
            swapOpacityOutDuration: 100
            swapScaleOutDuration: 100
            swapOpacityInDuration: 250
            swapScaleInDuration: 300
            text: {
                if (DisplayService.nightLightEnabled)
                    return "󰖔";
                if (!DisplayService.hasBacklight)
                    return "󰍹";
                if (displayRoot.brightnessPercent < 25)
                    return "󰃞";
                if (displayRoot.brightnessPercent < 60)
                    return "󰃟";
                if (displayRoot.brightnessPercent < 85)
                    return "󰃠";
                return "󰃡";
            }
            color: displayArea.containsMouse ? Theme.yellowBright : (DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.iconSize
            Behavior on color { Components.CAnim { duration: 150 } }
        }

        Text {
            text: displayRoot.labelText
            color: displayArea.containsMouse ? Theme.yellowBright : (DisplayService.hasBacklight ? Theme.fg : (DisplayService.nightLightEnabled ? Theme.orangeBright : Theme.fg3))
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Behavior on color { Components.CAnim { duration: 150 } }
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
