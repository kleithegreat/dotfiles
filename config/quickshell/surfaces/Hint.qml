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

    Ui.Surface {
        id: bubble

        x: Math.max(Metrics.gap, Math.min(parent.width - width - Metrics.gap, Sys.Hint.anchor - width / 2))
        y: 0
        width: caption.implicitWidth + Metrics.s4 * 2
        height: Metrics.controlHeight + Metrics.s1
        radius: height / 2
        tint: Theme.glassPanel
        elevation: 18

        opacity: Sys.Hint.showing ? 1 : 0
        scale: Sys.Hint.showing ? 1 : 0.92

        Behavior on opacity {
            Ui.Anim {
                duration: Motion.instant
            }
        }
        Behavior on scale {
            Ui.Anim {
                duration: Motion.quick
                easing.bezierCurve: Motion.enter
            }
        }
        Behavior on x {
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
