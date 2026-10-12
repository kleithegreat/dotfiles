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
            title: "Pointer"

            Ui.SliderRow {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                label: "Speed"
                minimum: -1
                maximum: 1
                value: Sys.Input.value("sensitivity", 0)
                pending: Sys.Input.staged["sensitivity"] !== undefined
                caption: Number(Sys.Input.value("sensitivity", 0)).toFixed(2)
                onCommitted: value => Sys.Input.set("sensitivity", Math.round(value * 100) / 100)
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.SliderRow {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                label: "Scrolling"
                minimum: 0.2
                maximum: 3
                value: Sys.Input.value("scroll_factor", 1)
                pending: Sys.Input.staged["scroll_factor"] !== undefined
                caption: Number(Sys.Input.value("scroll_factor", 1)).toFixed(2) + "×"
                onCommitted: value => Sys.Input.set("scroll_factor", Math.round(value * 100) / 100)
            }

            Ui.Divider {
                inset: Metrics.rowInset
                visible: Sys.Host.touchpad
            }

            Ui.SliderRow {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                visible: Sys.Host.touchpad
                label: "Touchpad scrolling"
                minimum: 0.05
                maximum: 1.5
                value: Sys.Input.value("touchpad_scroll_factor", 0.25)
                pending: Sys.Input.staged["touchpad_scroll_factor"] !== undefined
                caption: Number(Sys.Input.value("touchpad_scroll_factor", 0.25)).toFixed(2) + "×"
                onCommitted: value => Sys.Input.set("touchpad_scroll_factor", Math.round(value * 100) / 100)
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Acceleration"
                subtitle: "Flat moves the pointer the same distance however fast you move the mouse"
                interactive: false

                Ui.Choice {
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ label: "Flat", value: "flat" }, { label: "Adaptive", value: "adaptive" }]
                    current: Sys.Input.value("accel_profile", "flat")
                    onPicked: value => Sys.Input.set("accel_profile", value)
                }
            }
        }

        Ui.Group {
            title: "Cursor"

            Ui.Choice {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                options: Catalog.cursorThemes
                current: Sys.Appearance.value("cursor_theme", "")
                onPicked: value => Sys.Appearance.set("cursor_theme", value)
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "cursor"
                title: "Size"
                interactive: false

                Ui.Stepper {
                    anchors.verticalCenter: parent.verticalCenter
                    value: Sys.Appearance.value("cursor_size", 24)
                    minimum: 16
                    maximum: 64
                    onChanged: next => Sys.Appearance.set("cursor_size", next)
                }
            }
        }

        Ui.Group {
            title: "Icons"

            Ui.Choice {
                Layout.fillWidth: true
                Layout.margins: Metrics.s2
                options: Catalog.iconThemes
                current: Sys.Appearance.value("icon_theme", "")
                onPicked: value => Sys.Appearance.set("icon_theme", value)
            }
        }
    }
}
