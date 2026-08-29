import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.ui as Ui
import qs.services as Sys

PanelWindow {
    id: window

    anchors.top: true
    anchors.left: true
    anchors.right: true
    margins.top: Metrics.detachment - Metrics.s1
    implicitHeight: Metrics.rowHeight + Metrics.s4
    color: "transparent"
    visible: Sys.Hint.showing || bubble.opacity > 0.001
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.namespace: "quickshell:hint"
    WlrLayershell.layer: WlrLayer.Overlay

    // The strip's own width is only right once the layer surface has been
    // configured, which is one map behind the position the bubble needs.
    readonly property real span: window.screen ? window.screen.width : 0

    Ui.Surface {
        id: bubble

        x: Math.max(Metrics.gap, Math.min(window.span - width - Metrics.gap, Sys.Hint.anchor - width / 2))
        y: 0
        width: caption.implicitWidth + Metrics.s4 * 2
        height: Metrics.controlHeight + Metrics.s1
        radius: height / 2
        elevation: 18

        opacity: Sys.Hint.showing ? 1 : 0
        flatten: emergeAnim.running || fadeAnim.running || travelAnim.running

        // The hint belongs to the item under the pointer, so it unfolds from
        // that item's centre and hangs from its own top edge, the same
        // entrance every other summoned surface makes ([[quickshell]]).
        property real emerge: Sys.Hint.showing ? 1 : Motion.emergeScale

        transform: Scale {
            xScale: bubble.emerge
            yScale: bubble.emerge
            origin.x: Math.max(0, Math.min(bubble.width, Sys.Hint.anchor - bubble.x))
            origin.y: 0
        }

        Behavior on emerge {
            Ui.Anim {
                id: emergeAnim
                duration: Sys.Hint.showing ? Motion.quick : Motion.instant
                easing.bezierCurve: Sys.Hint.showing ? Motion.enter : Motion.exit
            }
        }

        Behavior on opacity {
            Ui.Anim {
                id: fadeAnim
                duration: Sys.Hint.showing ? Motion.quick : Motion.instant
                easing.bezierCurve: Sys.Hint.showing ? Motion.enter : Motion.exit
            }
        }

        // Geometry is placed while the hint is down and animated only while it
        // is up: this window unmaps between hints, and a move queued against a
        // window nobody can see runs in full once it maps ([[quickshell]]).
        Behavior on x {
            enabled: Sys.Hint.showing

            Ui.Anim {
                id: travelAnim
                duration: Motion.quick
                easing.bezierCurve: Motion.enter
            }
        }

        Behavior on width {
            enabled: Sys.Hint.showing

            Ui.Anim {
                duration: Motion.quick
                easing.bezierCurve: Motion.enter
            }
        }

        Ui.Label {
            id: caption
            anchors.centerIn: parent
            text: Sys.Hint.text
            role: "caption"
            color: Theme.text
        }
    }
}
