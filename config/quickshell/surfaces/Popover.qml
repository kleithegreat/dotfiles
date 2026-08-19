import QtQuick
import qs
import qs.ui as Ui

// A surface that grows out of the control that summoned it. Scaling from the
// panel's own centre is the single most common tell that a shell was assembled
// rather than designed: the panel appears to arrive from nowhere instead of
// unfolding from the thing you just pressed.
Item {
    id: root

    property bool shown: false
    property real anchor: 0
    property int panelWidth: Metrics.panelWide
    // Content declares its own height. Deriving it from the holder would make
    // the holder's height depend on the surface that depends on the holder.
    property int contentHeight: 0
    property int panelHeight: contentHeight + (padded ? Metrics.panelInset * 2 : 0)
    property bool padded: true

    default property alias content: body.data

    anchors.fill: parent
    visible: shown || surface.opacity > 0.001

    readonly property real _left: Math.max(Metrics.gap, Math.min(root.width - root.panelWidth - Metrics.gap, root.anchor - root.panelWidth / 2))

    Ui.Surface {
        id: surface

        x: root._left
        y: Metrics.detachment
        width: root.panelWidth
        height: root.panelHeight
        radius: Metrics.rPanel
        tint: Theme.glassPanel
        elevation: 34

        opacity: root.shown ? 1 : 0
        // Rendering to a texture while the scale runs keeps natively-rendered
        // text from re-rasterising on every frame of the entrance.
        layer.enabled: emergeAnim.running || fadeAnim.running

        property real emerge: root.shown ? 1 : Motion.emergeScale

        transform: Scale {
            xScale: surface.emerge
            yScale: surface.emerge
            origin.x: Math.max(0, Math.min(surface.width, root.anchor - surface.x))
            origin.y: 0
        }

        Behavior on emerge {
            Ui.Anim {
                id: emergeAnim
                duration: root.shown ? Motion.settled : Motion.quick
                easing.bezierCurve: root.shown ? Motion.enter : Motion.exit
            }
        }

        Behavior on opacity {
            Ui.Anim {
                id: fadeAnim
                duration: root.shown ? Motion.quick : Motion.instant
                easing.bezierCurve: root.shown ? Motion.enter : Motion.exit
            }
        }

        Behavior on height {
            Ui.Anim {
                duration: Motion.settled
                easing.bezierCurve: Motion.enter
            }
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.padded ? Metrics.panelInset : 0
        }
    }
}
