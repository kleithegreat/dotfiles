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
            title: "Layout"

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Inner gaps"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("hypr_gaps_in", 4)
                    minimum: 0
                    maximum: 40
                    onChanged: next => Sys.Appearance.set("hypr_gaps_in", next)
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Outer gaps"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("hypr_gaps_out", 6)
                    minimum: 0
                    maximum: 60
                    onChanged: next => Sys.Appearance.set("hypr_gaps_out", next)
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Border width"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("hypr_border_size", 0)
                    minimum: 0
                    maximum: 8
                    onChanged: next => Sys.Appearance.set("hypr_border_size", next)
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Corner radius"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("hypr_rounding", 8)
                    minimum: 0
                    maximum: 24
                    onChanged: next => Sys.Appearance.set("hypr_rounding", next)
                }
            }
        }

        Ui.Group {
            title: "Blur"
            footnote: "The shell's panels are translucent. With blur off they fall back to opaque, because translucency over an unblurred desktop is unreadable rather than atmospheric."

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Background blur"
                subtitle: Sys.Compositor.blurEnabled ? "Active" : "Off"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: String(Sys.Appearance.value("hypr_blur_enabled", false)) === "true"
                    onToggled: on => Sys.Appearance.set("hypr_blur_enabled", on)
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Radius"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("hypr_blur_size", 8)
                    minimum: 1
                    maximum: 20
                    onChanged: next => Sys.Appearance.set("hypr_blur_size", next)
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Passes"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("hypr_blur_passes", 3)
                    minimum: 1
                    maximum: 5
                    onChanged: next => Sys.Appearance.set("hypr_blur_passes", next)
                }
            }
        }

        Ui.Group {
            title: "Motion"

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Window animations"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: String(Sys.Appearance.value("hypr_animations_enabled", true)) === "true"
                    onToggled: on => Sys.Appearance.set("hypr_animations_enabled", on)
                }
            }
        }
    }
}
