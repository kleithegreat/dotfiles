import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            title: "Delivery"
            footnote: "Do Not Disturb keeps notifications out of the way while still recording them in the notification centre."

            Ui.ListRow {
                Layout.fillWidth: true
                icon: Sys.Notifications.dnd ? "bell-off" : "bell"
                title: "Do Not Disturb"
                subtitle: Sys.Notifications.dnd ? "Banners suppressed" : "Banners shown"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Notifications.dnd
                    onToggled: Sys.Notifications.toggleDnd()
                }
            }
        }

        Ui.Group {
            title: "History"

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "bell"
                title: "Recorded notifications"
                subtitle: Sys.Notifications.historyCount + " of " + Sys.Notifications.historyLimit + " kept"
                interactive: false

                Ui.Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Clear"
                    variant: "tinted"
                    interactive: Sys.Notifications.historyCount > 0
                    onClicked: Sys.Notifications.clearHistory()
                }
            }
        }
    }
}
