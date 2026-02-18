import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire

Item {
    id: volumeRoot
    implicitWidth: volumeRow.implicitWidth
    implicitHeight: volumeRow.implicitHeight
    signal clicked()

    property var sink: Pipewire.defaultAudioSink
    property real volume: sink?.audio?.volume ?? 0
    property bool muted: sink?.audio?.muted ?? false
    PwObjectTracker { objects: [volumeRoot.sink] }

    RowLayout {
        id: volumeRow; anchors.fill: parent; spacing: 4
        Text {
            text: { if (muted || volume === 0) return "󰝟"; if (volume < 0.33) return "󰕿"; if (volume < 0.66) return "󰖀"; return "󰕾"; }
            color: hoverA.containsMouse ? Theme.yellowBright : (muted ? Theme.fg4 : Theme.fg)
            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
        }
        Text {
            text: muted ? "Muted" : Math.round(volume * 100) + "%"
            color: hoverA.containsMouse ? Theme.yellowBright : (muted ? Theme.fg4 : Theme.fg)
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
        }
    }
    MouseArea {
        id: hoverA; anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton; hoverEnabled: true
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) { if (sink?.audio) sink.audio.muted = !sink.audio.muted; }
            else volumeRoot.clicked();
        }
        onWheel: (wheel) => {
            if (!sink?.audio) return;
            if (wheel.angleDelta.y > 0) sink.audio.volume = Math.min(1.0, volume + 0.05);
            else sink.audio.volume = Math.max(0.0, volume - 0.05);
        }
    }
}
