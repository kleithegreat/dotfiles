import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../../components" as Components

Components.WheelFlickable {
    id: root
    anchors.fill: parent
    contentHeight: audioCol.implicitHeight
    clip: true

    property var sink: AudioService.sink
    property var source: Pipewire.defaultAudioSource
    readonly property int valueLabelWidth: Theme.metricValueWidth
    readonly property int appLabelPreferredWidth: Math.max(Theme.fontSize * 9, 120)
    PwObjectTracker { objects: [root.sink, root.source] }

    ColumnLayout {
        id: audioCol
        width: parent.width
        spacing: 16

        Components.SettingsPaneHeader {
            title: "Audio"
            iconSource: "../icons/volume-high.svg"
        }

        // Output
        Components.SectionLabel { text: "OUTPUT" }

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/volume-high.svg"; color: Theme.fg }
            Text { text: "Output"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true }
            Text {
                text: (root.sink?.audio?.muted ?? false) ? "Muted" : "On"
                color: (root.sink?.audio?.muted ?? false) ? Theme.fg4 : Theme.fg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
            Components.ToggleSwitch {
                checked: !(root.sink?.audio?.muted ?? true)
                onToggled: {
                    AudioService.suppressOsd = true;
                    AudioService.toggleMute();
                    Qt.callLater(() => { AudioService.suppressOsd = false; });
                }
            }
        }
        Text { text: root.sink?.description ?? "No output"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon {
                source: (root.sink?.audio?.muted ?? false) ? "../icons/volume-mute.svg" : "../icons/volume-high.svg"
                color: Theme.fg4
                Layout.preferredWidth: Theme.metricIconWidth
            }
            Components.SliderTrack {
                fillColor: Theme.greenBright
                fraction: Math.min(1.0, root.sink?.audio?.volume ?? 0)
                onMoved: (f) => AudioService.setVolume(f)
                onPressStarted: AudioService.suppressOsd = true
                onPressEnded: Qt.callLater(() => { AudioService.suppressOsd = false; })
            }
            Text { text: Math.round((root.sink?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: root.valueLabelWidth; horizontalAlignment: Text.AlignRight }
        }

        // Input
        Components.Divider {}

        Components.SectionLabel { text: "INPUT" }

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/microphone.svg"; color: Theme.fg }
            Text { text: "Input"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true }
            Text {
                text: (root.source?.audio?.muted ?? true) ? "Muted" : "On"
                color: (root.source?.audio?.muted ?? true) ? Theme.fg4 : Theme.fg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
            Components.ToggleSwitch {
                checked: !(root.source?.audio?.muted ?? true)
                onToggled: {
                    AudioService.suppressOsd = true;
                    if (root.source?.audio) root.source.audio.muted = !root.source.audio.muted;
                    Qt.callLater(() => { AudioService.suppressOsd = false; });
                }
            }
        }
        Text { text: root.source?.description ?? "No input"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon {
                source: (root.source?.audio?.muted ?? true) ? "../icons/microphone-off.svg" : "../icons/microphone.svg"
                color: Theme.fg4
                Layout.preferredWidth: Theme.metricIconWidth
            }
            Components.SliderTrack {
                fillColor: Theme.aquaBright
                fraction: Math.min(1.0, root.source?.audio?.volume ?? 0)
                onMoved: (f) => { if (root.source?.audio) root.source.audio.volume = f; }
                onPressStarted: AudioService.suppressOsd = true
                onPressEnded: Qt.callLater(() => { AudioService.suppressOsd = false; })
            }
            Text { text: Math.round((root.source?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: root.valueLabelWidth; horizontalAlignment: Text.AlignRight }
        }

        // Applications
        Components.Divider {}

        Components.SectionLabel { text: "APPLICATIONS" }

        ColumnLayout {
            id: appCol
            Layout.fillWidth: true
            spacing: 8

            Repeater {
                id: appRepeater
                model: Pipewire.nodes
                RowLayout {
                    id: appRow; required property var modelData; required property int index
                    visible: modelData.isStream && !modelData.isSink && modelData.audio !== null
                    Layout.fillWidth: true; spacing: 8
                    PwObjectTracker { objects: [appRow.modelData] }

                    Text {
                        text: appRow.modelData.properties["application.name"] ?? appRow.modelData.description ?? "App"
                        color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        elide: Text.ElideRight
                        Layout.preferredWidth: root.appLabelPreferredWidth
                        Layout.maximumWidth: Math.max(root.appLabelPreferredWidth, Math.round(audioCol.width * 0.35))
                    }
                    Components.SliderTrack {
                        fillColor: Theme.yellowBright
                        knobSize: Theme.sliderKnobSizeSmall
                        fraction: Math.min(1.0, appRow.modelData.audio?.volume ?? 0)
                        onMoved: (f) => { if (appRow.modelData.audio) appRow.modelData.audio.volume = f; }
                        onPressStarted: AudioService.suppressOsd = true
                        onPressEnded: Qt.callLater(() => { AudioService.suppressOsd = false; })
                    }
                    Text { text: Math.round((appRow.modelData.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: root.valueLabelWidth; horizontalAlignment: Text.AlignRight }
                }
            }

            property int visibleAppCount: {
                let count = 0;
                for (let i = 0; i < appRepeater.count; i++) {
                    let item = appRepeater.itemAt(i);
                    if (item && item.visible) count++;
                }
                return count;
            }
            Text { visible: appCol.visibleAppCount === 0; text: "No applications playing"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        }
    }
}
