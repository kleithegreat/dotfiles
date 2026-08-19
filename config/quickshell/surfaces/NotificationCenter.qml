import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Popover {
    id: root

    required property ShellState state

    shown: state.isOpen("notifications")
    anchor: state.anchor
    panelWidth: Metrics.panelWide
    panelHeight: Math.min(520, Math.max(136, header.height + Metrics.s3 + column.implicitHeight + Metrics.panelInset * 2))

    ColumnLayout {
        anchors.fill: parent
        spacing: Metrics.s3

        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: Metrics.s2

            Ui.Label {
                text: "Notifications"
                role: "headline"
                Layout.fillWidth: true
            }

            Ui.Pressable {
                implicitWidth: Metrics.s6
                implicitHeight: Metrics.s6
                active: Sys.Notifications.dnd
                onClicked: Sys.Notifications.toggleDnd()

                Ui.Icon {
                    anchors.centerIn: parent
                    name: Sys.Notifications.dnd ? "bell-off" : "bell"
                    size: Metrics.iconSm
                    color: Sys.Notifications.dnd ? Theme.accent : Theme.textTertiary
                }
            }

            Ui.Button {
                text: "Clear"
                visible: Sys.Notifications.historyCount > 0
                onClicked: Sys.Notifications.clearHistory()
            }
        }

        Ui.Scroll {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentHeight: column.height
            visible: Sys.Notifications.historyCount > 0

            ColumnLayout {
                id: column
                width: list.width
                spacing: Metrics.s2

                Repeater {
                    model: Sys.Notifications.history

                    Ui.Card {
                        id: entry

                        required property string appName
                        required property string summary
                        required property string body
                        required property string age
                        required property int entryId

                        Layout.fillWidth: true
                        implicitHeight: text.implicitHeight + Metrics.s3 * 2

                        ColumnLayout {
                            id: text
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Metrics.s3
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Metrics.s2

                                Ui.Label {
                                    text: entry.appName
                                    role: "section"
                                    color: Theme.textTertiary
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Ui.Label {
                                    text: entry.age
                                    role: "caption"
                                    color: Theme.textQuaternary
                                }

                                Ui.Pressable {
                                    id: dismiss
                                    implicitWidth: Metrics.s5
                                    implicitHeight: Metrics.s5
                                    radius: Metrics.rControl
                                    onClicked: Sys.Notifications.forget(entry.entryId)

                                    Ui.Icon {
                                        anchors.centerIn: parent
                                        name: "close"
                                        size: Metrics.iconSm - 2
                                        color: dismiss.hovered ? Theme.text : Theme.textQuaternary
                                    }
                                }
                            }

                            Ui.Label {
                                Layout.fillWidth: true
                                text: entry.summary
                                role: "body"
                                font.weight: Theme.weightMedium
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                visible: text !== ""
                            }

                            Ui.Label {
                                Layout.fillWidth: true
                                text: entry.body
                                role: "callout"
                                wrapMode: Text.WordWrap
                                maximumLineCount: 4
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }
                    }
                }
            }
        }

        // A sibling of the list, never a child: inside the Flickable it would
        // centre on a content rect that is zero-high exactly when there is
        // nothing to show.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Sys.Notifications.historyCount === 0

            Column {
                anchors.centerIn: parent
                spacing: Metrics.s2

                Ui.Icon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: "bell"
                    size: Metrics.iconXl
                    color: Theme.textQuaternary
                }

                Ui.Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "No notifications"
                    role: "callout"
                    color: Theme.textTertiary
                }
            }
        }
    }
}
