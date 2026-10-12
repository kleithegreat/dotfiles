import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

PanelWindow {
    anchors.top: true
    margins.top: Metrics.detachment - pill.shadowPad
    implicitWidth: 240 + pill.shadowPad * 2
    implicitHeight: pill.height + pill.shadowPad * 2
    color: "transparent"
    visible: Sys.Osd.showing || pill.opacity > 0.001
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.namespace: "quickshell:osd"
    WlrLayershell.layer: WlrLayer.Overlay

    Ui.Surface {
        id: pill

        x: pill.shadowPad
        y: pill.shadowPad
        width: parent.width - pill.shadowPad * 2
        height: 44
        radius: height / 2
        elevation: 26

        opacity: Sys.Osd.showing ? 1 : 0
        scale: Sys.Osd.showing ? 1 : 0.9

        Behavior on opacity {
            Ui.Anim {
                duration: Sys.Osd.showing ? Motion.quick : Motion.settled
            }
        }
        Behavior on scale {
            Ui.Anim {
                duration: Sys.Osd.showing ? Motion.quick : Motion.settled
                easing.bezierCurve: Sys.Osd.showing ? Motion.enter : Motion.exit
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Metrics.s4
            anchors.rightMargin: Metrics.s4
            spacing: Metrics.s3

            Ui.Icon {
                name: Sys.Osd.icon
                color: Theme.text
            }

            Ui.Meter {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                fraction: Sys.Osd.value
                fill: Theme.text
            }

            Ui.Label {
                text: Sys.Osd.label
                role: "caption"
                numeric: true
                horizontalAlignment: Text.AlignRight
                Layout.preferredWidth: Metrics.s8 + Metrics.s2
            }
        }
    }
}
