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
            title: "Output"

            RowLayout {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                spacing: Metrics.s3

                Ui.Pressable {
                    implicitWidth: Metrics.s6
                    implicitHeight: Metrics.s6
                    onClicked: Sys.Audio.toggleMute()

                    Ui.Icon {
                        anchors.centerIn: parent
                        name: Sys.Audio.icon
                        color: Sys.Audio.muted ? Theme.textQuaternary : Theme.textSecondary
                    }
                }

                Ui.Slider {
                    id: level
                    Layout.fillWidth: true
                    value: Sys.Audio.volume
                    onMoved: value => Sys.Audio.setVolume(value)
                }

                Ui.Label {
                    text: Sys.Audio.percent + "%"
                    role: "caption"
                    numeric: true
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: Metrics.s8
                }
            }

            Binding {
                target: Sys.Osd
                property: "suppressed"
                value: true
                when: level.pressed
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "volume-high"
                title: "Device"
                subtitle: Sys.Audio.sinkName !== "" ? Sys.Audio.sinkName : "No output"
                interactive: false
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "volume-mute"
                title: "Mute"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Audio.muted
                    onToggled: Sys.Audio.toggleMute()
                }
            }
        }

        Ui.Group {
            title: "Input"

            Ui.ListRow {
                Layout.fillWidth: true
                icon: Sys.Audio.sourceMuted ? "microphone-off" : "microphone"
                title: "Microphone"
                subtitle: Sys.Audio.sourceName !== "" ? Sys.Audio.sourceName : "No input"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: !Sys.Audio.sourceMuted
                    onToggled: Sys.Audio.toggleSourceMute()
                }
            }
        }
    }
}
