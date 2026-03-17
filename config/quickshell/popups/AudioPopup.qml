import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../components" as Components

PanelWindow {
    id: audioPop
    property bool active: false; signal close()
    property var shellRoot: null
    property bool closing: false
    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:audio"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onActiveChanged: {
        if (active) {
            audioPanel.opacity = 0; audioPanel.scale = 0.92;
            audioOpenAnim.start();
        } else if (!closing) {
            closing = true; audioCloseAnim.start();
        }
    }

    SequentialAnimation {
        id: audioOpenAnim
        ParallelAnimation {
            NumberAnimation { target: audioPanel; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: audioPanel; property: "scale"; to: 1.0; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: audioCloseAnim
        ParallelAnimation {
            NumberAnimation { target: audioPanel; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
            NumberAnimation { target: audioPanel; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { audioPop.closing = false; } }
    }

    property var sink: Pipewire.defaultAudioSink
    property var source: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [audioPop.sink, audioPop.source] }

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: audioPop.close()
        MouseArea { anchors.fill: parent; onClicked: audioPop.close() }
    }

    Rectangle {
        id: audioPanel
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.audioPopupWidth; height: audioCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: 0.92
        transformOrigin: Item.TopRight
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: audioCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: Theme.listItemPadding

            // ── Output ──
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text { text: "󰕾  Output"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
                Text {
                    text: (audioPop.sink?.audio?.muted ?? false) ? "Muted" : "On"
                    color: (audioPop.sink?.audio?.muted ?? false) ? Theme.fg4 : Theme.fg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                }
                Components.ToggleSwitch {
                    checked: !(audioPop.sink?.audio?.muted ?? true)
                    onToggled: {
                        if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = true;
                        if (audioPop.sink?.audio) audioPop.sink.audio.muted = !audioPop.sink.audio.muted;
                        Qt.callLater(() => { if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = false; });
                    }
                }
            }
            Text { text: audioPop.sink?.description ?? "No output"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

            RowLayout { Layout.fillWidth: true; spacing: 8
                Text {
                    text: (audioPop.sink?.audio?.muted ?? false) ? "󰝟" : "󰕾"
                    color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * Math.min(1.0, audioPop.sink?.audio?.volume ?? 0)
                        radius: parent.radius; color: Theme.greenBright
                        Behavior on width { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        width: 12; height: 12; radius: 6
                        color: Theme.fg; y: (parent.height - height) / 2
                        x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1.0, audioPop.sink?.audio?.volume ?? 0) - width / 2))
                        scale: outSliderMouse.pressed ? 1.2 : (outSliderMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                        Behavior on x { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: outSliderMouse
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onPressed: { if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = true; }
                        onReleased: { Qt.callLater(() => { if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = false; }); }
                        onClicked: (mouse) => { if (audioPop.sink?.audio) audioPop.sink.audio.volume = mouse.x / parent.width; }
                        onPositionChanged: (mouse) => { if (pressed && audioPop.sink?.audio) audioPop.sink.audio.volume = Math.max(0, Math.min(1, mouse.x / parent.width)); }
                    }
                }
                Text { text: Math.round((audioPop.sink?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── Input ──
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text { text: "󰍬  Input"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
                Text {
                    text: (audioPop.source?.audio?.muted ?? true) ? "Muted" : "On"
                    color: (audioPop.source?.audio?.muted ?? true) ? Theme.fg4 : Theme.fg3
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                }
                Components.ToggleSwitch {
                    checked: !(audioPop.source?.audio?.muted ?? true)
                    onToggled: {
                        if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = true;
                        if (audioPop.source?.audio) audioPop.source.audio.muted = !audioPop.source.audio.muted;
                        Qt.callLater(() => { if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = false; });
                    }
                }
            }
            Text { text: audioPop.source?.description ?? "No input"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

            RowLayout { Layout.fillWidth: true; spacing: 8
                Text {
                    text: (audioPop.source?.audio?.muted ?? true) ? "󰍭" : "󰍬"
                    color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    Layout.preferredWidth: 16; horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    Layout.fillWidth: true; height: Theme.sliderHeight; radius: Theme.sliderHeight / 2; color: Theme.bg3
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: parent.width * Math.min(1.0, audioPop.source?.audio?.volume ?? 0)
                        radius: parent.radius; color: Theme.aquaBright
                        Behavior on width { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        width: 12; height: 12; radius: 6
                        color: Theme.fg; y: (parent.height - height) / 2
                        x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1.0, audioPop.source?.audio?.volume ?? 0) - width / 2))
                        scale: inSliderMouse.pressed ? 1.2 : (inSliderMouse.containsMouse ? 1.1 : 1.0)
                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                        Behavior on x { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    }
                    MouseArea {
                        id: inSliderMouse
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onPressed: { if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = true; }
                        onReleased: { Qt.callLater(() => { if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = false; }); }
                        onClicked: (mouse) => { if (audioPop.source?.audio) audioPop.source.audio.volume = mouse.x / parent.width; }
                        onPositionChanged: (mouse) => { if (pressed && audioPop.source?.audio) audioPop.source.audio.volume = Math.max(0, Math.min(1, mouse.x / parent.width)); }
                    }
                }
                Text { text: Math.round((audioPop.source?.audio?.volume ?? 0) * 100) + "%"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.preferredWidth: 32; horizontalAlignment: Text.AlignRight }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── Application Streams ──
            Text { text: "󰀻  Applications"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true }

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
                                    Behavior on width { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                }
                                Rectangle {
                                    width: 10; height: 10; radius: 5
                                    color: Theme.fg; y: (parent.height - height) / 2
                                    x: Math.max(0, Math.min(parent.width - width, parent.width * Math.min(1.0, appRow.modelData.audio?.volume ?? 0) - width / 2))
                                    scale: appSliderMouse.pressed ? 1.2 : (appSliderMouse.containsMouse ? 1.1 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                    Behavior on x { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                }
                                MouseArea {
                                    id: appSliderMouse
                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                                    onPressed: { if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = true; }
                                    onReleased: { Qt.callLater(() => { if (audioPop.shellRoot) audioPop.shellRoot.suppressOsd = false; }); }
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
