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
        elevation: 34

        opacity: root.shown ? 1 : 0
        flatten: emergeAnim.running || fadeAnim.running

        property real emerge: root.shown ? 1 : Motion.emergeScale

        transform: Scale {
            xScale: surface.emerge
            yScale: surface.emerge
            origin.x: Math.max(0, Math.min(surface.width, root.anchor - surface.x))
            origin.y: 0
        }

        Ui.Reveal on emerge {
            id: emergeAnim
            shownValue: 1
        }

        Ui.Reveal on opacity {
            id: fadeAnim
            shownValue: 1
            enterDuration: Motion.quick
            exitDuration: Motion.instant
            enterCurve: Motion.standard
        }

        // Content re-laying out under an open panel animates; the height the
        // panel opens at belongs to the entrance, not to a transition of its own.
        Behavior on height {
            enabled: !emergeAnim.running && !fadeAnim.running

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
