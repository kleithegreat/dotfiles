import qs
import QtQuick
import "../components" as Components

Item {
    id: volumeRoot
    implicitWidth: volIcon.implicitWidth
    implicitHeight: volIcon.implicitHeight
    signal clicked()

    readonly property real volume: AudioService.volume
    readonly property bool muted: AudioService.muted
    readonly property string tooltipText: muted ? "Muted" : "Volume: " + Math.round(volume * 100) + "%"

    Components.StyledIcon {
        id: volIcon
        anchors.centerIn: parent
        animate: true
        source: AudioService.volumeIconFor(Math.round(volume * 100), muted)
        color: hoverA.containsMouse ? Theme.yellowBright : (muted ? Theme.fg4 : Theme.fg)
        Behavior on color { Components.CAnim { duration: Theme.animHover } }
    }
    Components.BarTooltipArea {
        id: hoverA; tip: volumeRoot.tooltipText
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onClicked: (mouse) => {
            if (mouse.button === Qt.MiddleButton) {
                AudioService.suppressOsdDuring(() => AudioService.toggleMute());
            }
            else volumeRoot.clicked();
        }
        onWheel: (wheel) => {
            AudioService.suppressOsdDuring(() => {
                if (wheel.angleDelta.y > 0) AudioService.incrementVolume(0.05);
                else AudioService.decrementVolume(0.05);
            });
        }
    }
}
