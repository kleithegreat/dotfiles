import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    anchors.fill: parent
    contentHeight: notificationsCol.implicitHeight
    clip: true

    ColumnLayout {
        id: notificationsCol
        width: parent.width
        spacing: 16

        Components.SettingsPaneHeader { title: "Notifications"; iconSource: "../icons/bell.svg" }

        Components.SectionLabel { text: "DO NOT DISTURB" }

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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    text: NotificationService.doNotDisturb
                        ? "Popups are suppressed while history keeps collecting."
                        : "Popups are shown normally and still saved to history."
                    color: Theme.fg3
                    font.family: Theme.fontFamily
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

        Components.Divider {}

        Components.SectionLabel { text: "HISTORY" }

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
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                }

                Text {
                    text: NotificationService.historyCount === 0
                        ? "The drawer is empty until new notifications arrive."
                        : "Clear the drawer history without changing the DND state."
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }

            Components.ActionButton {
                visible: NotificationService.historyCount > 0
                text: "Clear"
                textColor: Theme.fg4
                hoverTextColor: Theme.redBright
                onClicked: NotificationService.clearHistory()
            }
        }
    }
}
