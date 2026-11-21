import QtQuick
import qs
import qs.ui as Ui

Item {
    id: root

    property bool shown: false
    property real anchor: 0
    property int panelWidth: Metrics.panelWide
    // Declared by the content: derived from the holder it is a binding loop ([[quickshell]]).
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

        // The opening height belongs to the entrance, not to this transition.
        Behavior on height {
            enabled: root.shown && !emergeAnim.running && !fadeAnim.running

            Ui.Anim {
                duration: Motion.settled
                easing.bezierCurve: Motion.enter
            }
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.padded ? Metrics.panelInset : 0

            // The contents settle a beat after the panel, from just above.
            opacity: root.shown ? 1 : 0
            property real drop: root.shown ? 0 : -8
            transform: Translate {
                y: body.drop
            }

            Ui.Reveal on opacity {
                shownValue: 1
                enterDelay: Motion.follow
                enterDuration: Motion.quick
                enterCurve: Motion.standard
                exitDuration: Motion.instant
            }
            Ui.Reveal on drop {
                shownValue: 0
                enterDelay: Motion.follow
            }
        }
    }
}
