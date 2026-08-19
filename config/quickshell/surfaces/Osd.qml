import QtQuick
import Quickshell
import Quickshell.Wayland
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

PanelWindow {
    id: window

    anchors.top: true
    margins.top: Metrics.detachment
    implicitWidth: 240
    implicitHeight: 44 + Metrics.s6
    color: "transparent"
    visible: Sys.Osd.showing || pill.opacity > 0.001
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}
    WlrLayershell.namespace: "quickshell:osd"
    WlrLayershell.layer: WlrLayer.Overlay

    Ui.Surface {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: parent.width
        height: 44
        radius: height / 2
        tint: Theme.glassPanel
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

            Rectangle {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                height: Metrics.trackHeight
                radius: height / 2
                color: Theme.fillTrack
                antialiasing: true

                Rectangle {
                    width: parent.width * Sys.Osd.value
                    height: parent.height
                    radius: parent.radius
                    color: Theme.text
                    antialiasing: true

                    Behavior on width {
                        Ui.Anim {
                            duration: Motion.instant
                        }
                    }
                }
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
