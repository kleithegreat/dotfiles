import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    readonly property string directory: Sys.Appearance.value("wallpaper_dir", "")
    readonly property string current: Sys.Appearance.value("wallpaper", "")

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            title: "Options"

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "palette"
                title: "Tint the scheme from the wallpaper"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: String(Sys.Appearance.value("filter_wallpaper", false)) === "true"
                    onToggled: on => Sys.Appearance.set("filter_wallpaper", on)
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Metrics.s2
            rowSpacing: Metrics.s2

            Repeater {
                model: Sys.Appearance.wallpapers

                Ui.Pressable {
                    id: option

                    required property string modelData
                    readonly property string path: root.directory + "/" + option.modelData
                    readonly property bool selected: root.current === option.path

                    Layout.fillWidth: true
                    Layout.preferredHeight: width * 9 / 16
                    radius: Metrics.rCard
                    showFill: false
                    pressScale: 0.98
                    onClicked: Sys.Appearance.set("wallpaper", option.path)

                    Ui.Card {
                        anchors.fill: parent
                        clip: true
                        border.color: option.selected ? Theme.accent : Theme.separator

                        Image {
                            anchors.fill: parent
                            source: "file://" + option.path
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 480
                            asynchronous: true
                            smooth: true
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: Metrics.rCard
                        color: option.pressed ? Theme.fillPress : option.hovered ? Theme.fillHover : "transparent"
                        antialiasing: true

                        Behavior on color {
                            Ui.Tint {}
                        }
                    }

                    Ui.Icon {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: Metrics.s2
                        name: "circle-check-filled"
                        color: Theme.accent
                        visible: option.selected
                    }
                }
            }
        }
    }
}
