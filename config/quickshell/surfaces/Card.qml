import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Layouts
import qs
import qs.ui as Ui

// A card that rises from the bottom edge for something happening nearby: an
// AirPods case opening, an AirDrop offer. Its content is laid out in a column.
PanelWindow {
    id: window

    property bool shown: false
    default property alias content: body.data

    readonly property int cardElevation: 30
    readonly property int pad: Metrics.shadowReach(cardElevation)

    anchors.bottom: true
    margins.bottom: Metrics.detachment - pad
    implicitWidth: 340 + pad * 2
    implicitHeight: card.height + pad * 2
    color: "transparent"
    visible: shown || card.opacity > 0.001
    exclusionMode: ExclusionMode.Ignore
    mask: Region {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
    }
    WlrLayershell.layer: WlrLayer.Overlay

    Ui.Surface {
        id: card

        x: window.pad
        y: window.pad
        width: 340
        height: body.implicitHeight + Metrics.s5 * 2
        radius: Metrics.rPanel
        elevation: window.cardElevation

        opacity: window.shown ? 1 : 0
        property real rise: window.shown ? 0 : 48
        transform: Translate {
            y: card.rise
        }

        Behavior on opacity {
            Ui.Anim {
                duration: Motion.settled
            }
        }
        Behavior on rise {
            Ui.Anim {
                duration: Motion.settled
                easing.bezierCurve: window.shown ? Motion.enter : Motion.exit
            }
        }

        ColumnLayout {
            id: body

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Metrics.s5
            spacing: Metrics.s4
        }
    }
}
