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
    property bool saving: false
    property string removing: ""
    property var captured: ["scheme", "icons"]

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
                    id: preset

                    required property string modelData

                    Layout.fillWidth: true
                    icon: "palette"
                    title: modelData
                    onClicked: Sys.Appearance.applyPreset(preset.modelData)

                    Ui.Button {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.removing === preset.modelData ? "Delete" : ""
                        icon: root.removing === preset.modelData ? "" : "close"
                        variant: root.removing === preset.modelData ? "destructive" : "plain"
                        onClicked: {
                            if (root.removing === preset.modelData) {
                                Sys.Appearance.deletePreset(preset.modelData);
                                root.removing = "";
                            } else {
                                root.removing = preset.modelData;
                            }
                        }
                    }
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "circle-check"
                title: root.saving ? "What should it capture?" : "Save current appearance"
                onClicked: {
                    root.saving = !root.saving;
                    root.removing = "";
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: Metrics.rowInset
                Layout.rightMargin: Metrics.rowInset
                Layout.bottomMargin: Metrics.s2
                spacing: Metrics.s2
                visible: root.saving

                Flow {
                    Layout.fillWidth: true
                    spacing: Metrics.s1

                    Repeater {
                        model: Sys.Appearance.aspects

                        Ui.Pressable {
                            id: aspect

                            required property var modelData
                            readonly property bool chosen: root.captured.indexOf(aspect.modelData.id) >= 0

                            implicitWidth: tag.implicitWidth + Metrics.s3 * 2
                            implicitHeight: Metrics.controlHeight
                            radius: Metrics.rControl
                            active: aspect.chosen
                            onClicked: root.captured = aspect.chosen ? root.captured.filter(id => id !== aspect.modelData.id) : root.captured.concat([aspect.modelData.id])

                            Ui.Label {
                                id: tag
                                anchors.centerIn: parent
                                text: aspect.modelData.label
                                role: "callout"
                                color: aspect.chosen ? Theme.text : Theme.textSecondary
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Metrics.s2

                    Ui.Field {
                        id: presetName
                        Layout.fillWidth: true
                        placeholder: "Preset name"
                        onAccepted: store.clicked()
                    }

                    Ui.Button {
                        id: store
                        text: "Save"
                        variant: "filled"
                        interactive: presetName.text.trim() !== "" && root.captured.length > 0
                        onClicked: {
                            if (Sys.Appearance.savePreset(presetName.text.trim(), root.captured)) {
                                presetName.text = "";
                                root.saving = false;
                            }
                        }
                    }
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
