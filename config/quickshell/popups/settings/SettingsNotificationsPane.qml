import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    anchors.fill: parent
    contentHeight: notificationsCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: notificationsCol
        width: parent.width
        spacing: 16

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/bell.svg"; color: Theme.fg }
            Text { text: "Notifications"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text {
            text: "DO NOT DISTURB"
            color: Theme.fg4
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Components.Icon {
                source: NotificationService.doNotDisturb ? "../icons/bell-off.svg" : "../icons/bell.svg"
                color: NotificationService.doNotDisturb ? Theme.orangeBright : Theme.fg4
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Do Not Disturb"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    text: NotificationService.doNotDisturb
                        ? "Popups are suppressed while history keeps collecting."
                        : "Popups are shown normally and still saved to history."
                    color: Theme.fg3
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Components.ToggleSwitch {
                checked: NotificationService.doNotDisturb
                onToggled: NotificationService.toggleDnd()
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text {
            text: "HISTORY"
            color: Theme.fg4
            font.family: Theme.systemFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Components.Icon {
                source: "../icons/bell.svg"
                color: Theme.fg4
                Layout.alignment: Qt.AlignVCenter
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: NotificationService.historyCount === 0
                        ? "No notifications saved"
                        : NotificationService.historyCount === 1
                            ? "1 notification saved"
                            : NotificationService.historyCount + " notifications saved"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    text: NotificationService.historyCount === 0
                        ? "The drawer is empty until new notifications arrive."
                        : "Clear the drawer history without changing the DND state."
                    color: Theme.fg3
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Rectangle {
                visible: NotificationService.historyCount > 0
                width: clearLabel.implicitWidth + Theme.btnPaddingH * 2
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: clearArea.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color {
                    Components.CAnim {
                        duration: Theme.animHover
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Theme.animCurveStandard
                    }
                }

                Text {
                    id: clearLabel
                    anchors.centerIn: parent
                    text: "Clear"
                    color: clearArea.containsMouse ? Theme.redBright : Theme.fg4
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Behavior on color {
                        Components.CAnim {
                            duration: Theme.animHover
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                }

                Components.HoverLayer {
                    id: clearArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: NotificationService.clearHistory()
                }
            }
        }
    }
}
