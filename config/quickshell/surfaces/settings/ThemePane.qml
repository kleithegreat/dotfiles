import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    // The scheme catalog lives beside the wallpapers the backend already
    // reports, so the shell never carries a second copy of the repo layout.
    readonly property string schemeDir: {
        const wallpapers = Sys.Appearance.value("wallpaper_dir", "");
        return wallpapers === "" ? "" : wallpapers.replace(/\/wallpapers\/?$/, "/colors");
    }

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            title: "Presets"
            footnote: "A preset is a partial patch, not a snapshot: it changes what it names and leaves everything else alone."

            Repeater {
                model: Sys.Appearance.presets

                Ui.ListRow {
                    required property string modelData
                    Layout.fillWidth: true
                    icon: "palette"
                    title: modelData
                    chevron: true
                    onClicked: Sys.Appearance.applyPreset(modelData)
                }
            }
        }

        Ui.Group {
            title: "Colour scheme"

            ColumnLayout {
                Layout.fillWidth: true
                Layout.margins: Metrics.s1
                spacing: Metrics.s1

                Repeater {
                    model: Sys.Appearance.schemes

                    Ui.Swatch {
                        required property string modelData
                        Layout.fillWidth: true
                        scheme: modelData
                        directory: root.schemeDir
                        selected: Sys.Appearance.value("color_scheme", "") === modelData
                        onClicked: Sys.Appearance.set("color_scheme", modelData)
                    }
                }
            }
        }
    }
}
