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
            title: "Interface"

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "typography"
                title: "Typeface"
                interactive: false
            }

            Ui.Choice {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.rowInset
                Layout.bottomMargin: Metrics.s2
                options: Catalog.systemFonts
                current: Sys.Appearance.value("system_font", "")
                showsMissing: true
                onPicked: value => Sys.Appearance.set("system_font", value)
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Size"
                subtitle: "Base size everything else is measured from"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("font_size", 11)
                    minimum: 8
                    maximum: 20
                    onChanged: next => Sys.Appearance.set("font_size", next)
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Shell offset"
                subtitle: "Applied on top of the base size in this shell"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("quickshell_font_size_offset", 0)
                    minimum: -4
                    maximum: 8
                    onChanged: next => Sys.Appearance.set("quickshell_font_size_offset", next)
                }
            }
        }

        Ui.Group {
            title: "Monospace"

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "typography"
                title: "Typeface"
                interactive: false
            }

            Ui.Choice {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.rowInset
                Layout.bottomMargin: Metrics.s2
                options: Catalog.monoFonts
                current: Sys.Appearance.value("mono_font", "")
                showsMissing: true
                onPicked: value => Sys.Appearance.set("mono_font", value)
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Size"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("mono_font_size", 11)
                    minimum: 8
                    maximum: 22
                    onChanged: next => Sys.Appearance.set("mono_font_size", next)
                }
            }
        }

        Ui.Group {
            title: "Per-application offsets"
            footnote: "Editors and terminals disagree about what a point is. These correct for that without moving the base size."

            Repeater {
                model: [
                    { key: "alacritty_mono_font_size_offset", label: "Alacritty" },
                    { key: "ghostty_mono_font_size_offset", label: "Ghostty" },
                    { key: "vscode_mono_font_size_offset", label: "VS Code" },
                    { key: "zed_mono_font_size_offset", label: "Zed" },
                    { key: "neovide_mono_font_size_offset", label: "Neovide" },
                    { key: "gtk_mono_font_size_offset", label: "GTK" },
                    { key: "qt_mono_font_size_offset", label: "Qt" }
                ]

                Ui.ListRow {
                    id: offset

                    required property var modelData

                    Layout.fillWidth: true
                    title: modelData.label
                    interactive: false

                    Ui.Stepper {
                        anchors.verticalCenter: parent.verticalCenter
                        value: Sys.Appearance.value(offset.modelData.key, 0)
                        minimum: -6
                        maximum: 8
                        onChanged: next => Sys.Appearance.set(offset.modelData.key, next)
                    }
                }
            }
        }
    }
}
