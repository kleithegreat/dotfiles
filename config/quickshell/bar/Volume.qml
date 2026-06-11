import qs
import QtQuick
import QtQuick.Layouts
import "../components" as Components

Item {
    id: volumeRoot
    implicitWidth: volumeRow.implicitWidth
    implicitHeight: volumeRow.implicitHeight
    signal clicked()

    property real volume: AudioService.volume
    property bool muted: AudioService.muted
    property string tooltipText: muted ? "Muted" : "Volume: " + Math.round(volume * 100) + "%"

    RowLayout {
        id: volumeRow; anchors.fill: parent; spacing: 4
        Components.StyledIcon {
            id: volIcon
            animate: true
            source: AudioService.volumeIconFor(Math.round(volume * 100), muted)
            color: hoverA.containsMouse ? Theme.yellowBright : (muted ? Theme.fg4 : Theme.fg)
            Behavior on color { Components.CAnim { duration: Theme.animHover } }
        }
    }
    MouseArea {
        id: hoverA; anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = volumeRoot.mapToGlobal(Qt.point(volumeRoot.width / 2, volumeRoot.height));
                TooltipService.show(volumeRoot.tooltipText, p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
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
