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
    boundsBehavior: Flickable.StopAtBounds

    property var sink: AudioService.sink
    property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [root.sink, root.source] }

    ColumnLayout {
        id: audioCol
        width: parent.width
        spacing: 16

        // ── Header ───────────────────────────────────────────

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/volume-high.svg"; color: Theme.fg }
            Text { text: "Audio"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        // ── Output ───────────────────────────────────────────

        Text { text: "OUTPUT"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

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
                Layout.preferredWidth: 16
            }
            Rectangle {
                Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * Math.min(1.0, root.sink?.audio?.volume ?? 0)
                    radius: parent.radius; color: Theme.greenBright
                    Behavior on width { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                }
                Rectangle {
                    width: 12; height: 12; radius: 6; color: Theme.fg
                    y: (parent.height - height) / 2
                    x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1.0, root.sink?.audio?.volume ?? 0) - width / 2))
                    scale: outSlider.pressed ? 1.2 : (outSlider.containsMouse ? 1.1 : 1.0)
                    Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    Behavior on x { SpringAnimation { spring: 4; damping: 0.4 } }
                }
                Components.HoverLayer {
                    id: outSlider; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                    onPressed: { AudioService.suppressOsd = true; }
                    onReleased: { Qt.callLater(() => { AudioService.suppressOsd = false; }); }
                    onClicked: (mouse) => { AudioService.setVolume(mouse.x / parent.width); }
                    onPositionChanged: (mouse) => { if (pressed) AudioService.setVolume(mouse.x / parent.width); }
                }
            }
            Text { text: Math.round((root.sink?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
        }

        // ── Input ────────────────────────────────────────────

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "INPUT"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

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
                Layout.preferredWidth: 16
            }
            Rectangle {
                Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * Math.min(1.0, root.source?.audio?.volume ?? 0)
                    radius: parent.radius; color: Theme.aquaBright
                    Behavior on width { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                }
                Rectangle {
                    width: 12; height: 12; radius: 6; color: Theme.fg
                    y: (parent.height - height) / 2
                    x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1.0, root.source?.audio?.volume ?? 0) - width / 2))
                    scale: inSlider.pressed ? 1.2 : (inSlider.containsMouse ? 1.1 : 1.0)
                    Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                    Behavior on x { SpringAnimation { spring: 4; damping: 0.4 } }
                }
                Components.HoverLayer {
                    id: inSlider; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                    onPressed: { AudioService.suppressOsd = true; }
                    onReleased: { Qt.callLater(() => { AudioService.suppressOsd = false; }); }
                    onClicked: (mouse) => { if (root.source?.audio) root.source.audio.volume = mouse.x / parent.width; }
                    onPositionChanged: (mouse) => { if (pressed && root.source?.audio) root.source.audio.volume = Math.max(0, Math.min(1, mouse.x / parent.width)); }
                }
            }
            Text { text: Math.round((root.source?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
        }

        // ── Applications ─────────────────────────────────────

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "APPLICATIONS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

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
                        elide: Text.ElideRight; Layout.preferredWidth: 100
                    }
                    Rectangle {
                        Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3
                        Rectangle {
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            width: parent.width * Math.min(1.0, appRow.modelData.audio?.volume ?? 0)
                            radius: parent.radius; color: Theme.yellowBright
                            Behavior on width { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        }
                        Rectangle {
                            width: 10; height: 10; radius: 5; color: Theme.fg
                            y: (parent.height - height) / 2
                            x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1.0, appRow.modelData.audio?.volume ?? 0) - width / 2))
                            scale: appSlider.pressed ? 1.2 : (appSlider.containsMouse ? 1.1 : 1.0)
                            Behavior on scale { Components.Anim { duration: Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                            Behavior on x { SpringAnimation { spring: 4; damping: 0.4 } }
                        }
                        Components.HoverLayer {
                            id: appSlider; hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                            onPressed: { AudioService.suppressOsd = true; }
                            onReleased: { Qt.callLater(() => { AudioService.suppressOsd = false; }); }
                            onClicked: (mouse) => { if (appRow.modelData.audio) appRow.modelData.audio.volume = mouse.x / parent.width; }
                            onPositionChanged: (mouse) => { if (pressed && appRow.modelData.audio) appRow.modelData.audio.volume = Math.max(0, Math.min(1, mouse.x / parent.width)); }
                        }
                    }
                    Text { text: Math.round((appRow.modelData.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
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
