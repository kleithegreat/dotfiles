import qs
import QtQuick
import QtQuick.Layouts

Item {
    id: volumeRoot
    implicitWidth: volumeRow.implicitWidth
    implicitHeight: volumeRow.implicitHeight
    signal clicked()

    property real volume: AudioService.volume
    property bool muted: AudioService.muted

    RowLayout {
        id: volumeRow; anchors.fill: parent; spacing: 4
        Text {
            id: volIcon
            text: { if (muted || volume === 0) return "󰝟"; if (volume < 0.33) return "󰕿"; if (volume < 0.66) return "󰖀"; return "󰕾"; }
            color: hoverA.containsMouse ? Theme.yellowBright : (muted ? Theme.fg4 : Theme.fg)
            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
            Behavior on text {
                SequentialAnimation {
                    NumberAnimation { target: volIcon; property: "opacity"; to: 0; duration: Theme.animFast; easing.type: Easing.InQuad }
                    PropertyAction { target: volIcon; property: "text" }
                    NumberAnimation { target: volIcon; property: "opacity"; to: 1; duration: Theme.animNormal; easing.type: Easing.OutCubic }
                }
            }
            Behavior on color { ColorAnimation { duration: 150 } }
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
            if (mouse.button === Qt.MiddleButton) {
                AudioService.suppressOsd = true;
                AudioService.toggleMute();
                Qt.callLater(() => { AudioService.suppressOsd = false; });
            }
            else volumeRoot.clicked();
        }
        onWheel: (wheel) => {
            AudioService.suppressOsd = true;
            if (wheel.angleDelta.y > 0) AudioService.incrementVolume(0.05);
            else AudioService.decrementVolume(0.05);
            Qt.callLater(() => { AudioService.suppressOsd = false; });
        }
    }
}
