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

            Ui.SliderRow {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                icon: Sys.Audio.icon
                iconColor: Sys.Audio.muted ? Theme.textQuaternary : Theme.textSecondary
                iconInteractive: true
                value: Sys.Audio.volume
                caption: Sys.Audio.percent + "%"
                onIconClicked: Sys.Audio.toggleMute()
                onMoved: level => Sys.Audio.setVolume(level)
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Repeater {
                model: Sys.Audio.sinks

                Ui.ListRow {
                    required property var modelData

                    Layout.fillWidth: true
                    icon: modelData.description.indexOf("AirPods") >= 0 ? "airpods" : modelData.properties["device.api"] === "bluez5" ? "bluetooth-on" : "volume-high"
                    title: modelData.description
                    selected: modelData === Sys.Audio.sink
                    onClicked: Sys.Audio.useSink(modelData)
                }
            }

            Ui.ListRow {
                Layout.fillWidth: true
                visible: Sys.Audio.sinks.length === 0
                icon: "volume-mute"
                title: "No output"
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
