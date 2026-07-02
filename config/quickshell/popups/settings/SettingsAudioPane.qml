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

    // Device section: mute status/toggle header, description, volume slider.
    component AudioDeviceSection: ColumnLayout {
        id: section

        required property var device
        required property string title
        required property string deviceIcon
        required property string mutedIcon
        required property string emptyText
        required property color fillColor
        property bool mutedFallback: false

        readonly property bool isMuted: section.device?.audio?.muted ?? section.mutedFallback

        signal muteToggled()
        signal volumeMoved(real fraction)

        Layout.fillWidth: true
        spacing: 16

        Components.SectionLabel { text: section.title.toUpperCase() }

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: section.deviceIcon; color: Theme.fg }
            Text { text: section.title; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true }
            Text {
                text: section.isMuted ? "Muted" : "On"
                color: section.isMuted ? Theme.fg4 : Theme.fg3
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
            Components.ToggleSwitch {
                checked: !(section.device?.audio?.muted ?? true)
                onToggled: AudioService.suppressOsdDuring(() => section.muteToggled())
            }
        }
        Text { text: section.device?.description ?? section.emptyText; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon {
                source: section.isMuted ? section.mutedIcon : section.deviceIcon
                color: Theme.fg4
                Layout.preferredWidth: Theme.metricIconWidth
            }
            Components.SliderTrack {
                fillColor: section.fillColor
                fraction: Math.min(1.0, section.device?.audio?.volume ?? 0)
                onMoved: (f) => section.volumeMoved(f)
                onPressStarted: AudioService.suppressOsd = true
                onPressEnded: Qt.callLater(() => { AudioService.suppressOsd = false; })
            }
            Text { text: Math.round((section.device?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: root.valueLabelWidth; horizontalAlignment: Text.AlignRight }
        }
    }

    ColumnLayout {
        id: audioCol
        width: parent.width
        spacing: 16

        Components.SettingsPaneHeader {
            title: "Audio"
            iconSource: "../icons/volume-high.svg"
        }

        AudioDeviceSection {
            device: root.sink
            title: "Output"
            deviceIcon: "../icons/volume-high.svg"
            mutedIcon: "../icons/volume-mute.svg"
            emptyText: "No output"
            fillColor: Theme.greenBright
            onMuteToggled: AudioService.toggleMute()
            onVolumeMoved: (f) => AudioService.setVolume(f)
        }

        Components.Divider {}

        AudioDeviceSection {
            device: root.source
            title: "Input"
            deviceIcon: "../icons/microphone.svg"
            mutedIcon: "../icons/microphone-off.svg"
            emptyText: "No input"
            fillColor: Theme.aquaBright
            mutedFallback: true
            onMuteToggled: {
                if (root.source?.audio)
                    root.source.audio.muted = !root.source.audio.muted;
            }
            onVolumeMoved: (f) => {
                if (root.source?.audio)
                    root.source.audio.volume = f;
            }
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
                    id: appRow; required property var modelData
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
