import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

PanelWindow {
    id: audioPop
    property bool active: false; signal close()
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:audio"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property var sink: Pipewire.defaultAudioSink
    property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [audioPop.sink, audioPop.source] }

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: audioPop.close()
        MouseArea { anchors.fill: parent; onClicked: audioPop.close() }
    }

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut + 80
        width: Theme.audioPopupWidth; height: audioCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: audioCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 10

            // ── Output ──
            Text { text: "Output"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { text: audioPop.sink?.description ?? "No output"; color: Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

            RowLayout { Layout.fillWidth: true; spacing: 8
                Text {
                    text: (audioPop.sink?.audio?.muted ?? false) ? "󰝟" : "󰕾"
                    color: outMuteA.containsMouse ? Theme.yellowBright : Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    MouseArea { id: outMuteA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { if (audioPop.sink?.audio) audioPop.sink.audio.muted = !audioPop.sink.audio.muted; } }
                }
                Rectangle {
                    Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * Math.min(1.0, audioPop.sink?.audio?.volume ?? 0)
                        radius: parent.radius; color: Theme.greenBright
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => { if (audioPop.sink?.audio) audioPop.sink.audio.volume = mouse.x / parent.width; }
                        onPositionChanged: (mouse) => { if (pressed && audioPop.sink?.audio) audioPop.sink.audio.volume = Math.max(0, Math.min(1, mouse.x / parent.width)); }
                    }
                }
                Text { text: Math.round((audioPop.sink?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── Input ──
            Text { text: "Input"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text {
                    text: (audioPop.source?.audio?.muted ?? true) ? "󰍭" : "󰍬"
                    color: inMuteA.containsMouse ? Theme.yellowBright : Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    MouseArea { id: inMuteA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { if (audioPop.source?.audio) audioPop.source.audio.muted = !audioPop.source.audio.muted; } }
                }
                Rectangle {
                    Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * Math.min(1.0, audioPop.source?.audio?.volume ?? 0)
                        radius: parent.radius; color: Theme.aquaBright
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => { if (audioPop.source?.audio) audioPop.source.audio.volume = mouse.x / parent.width; }
                        onPositionChanged: (mouse) => { if (pressed && audioPop.source?.audio) audioPop.source.audio.volume = Math.max(0, Math.min(1, mouse.x / parent.width)); }
                    }
                }
                Text { text: Math.round((audioPop.source?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── Application Streams ──
            Text { text: "Applications"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }

            Flickable {
                Layout.fillWidth: true; Layout.maximumHeight: 200; Layout.minimumHeight: 30
                contentHeight: appCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: appCol; width: parent.width; spacing: 8
                    Repeater {
                        id: appRepeater
                        model: Pipewire.nodes
                        RowLayout {
                            id: appRow; required property var modelData; required property int index
                            // Show only audio output streams (apps playing audio)
                            visible: modelData.isStream && !modelData.isSink && modelData.audio !== null
                            width: appCol.width; spacing: 8
                            PwObjectTracker { objects: [appRow.modelData] }

                            Text {
                                text: appRow.modelData.properties["application.name"] ?? appRow.modelData.description ?? "App"
                                color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight; Layout.preferredWidth: 80
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                    width: parent.width * Math.min(1.0, appRow.modelData.audio?.volume ?? 0)
                                    radius: parent.radius; color: Theme.yellowBright
                                }
                                MouseArea {
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => { if (appRow.modelData.audio) appRow.modelData.audio.volume = mouse.x / parent.width; }
                                    onPositionChanged: (mouse) => { if (pressed && appRow.modelData.audio) appRow.modelData.audio.volume = Math.max(0, Math.min(1, mouse.x / parent.width)); }
                                }
                            }
                            Text { text: Math.round((appRow.modelData.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
                        }
                    }

                    Text { visible: appRepeater.count === 0; text: "No applications playing"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }
        }
    }
}
