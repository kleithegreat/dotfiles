import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.ui as Ui
import qs.services as Sys

PanelWindow {
    id: window

    anchors.bottom: true
    margins.bottom: Metrics.s6
    implicitWidth: Math.min(560, body.implicitWidth + Metrics.s5 * 2)
    implicitHeight: 44 + Metrics.s5
    color: "transparent"
    visible: Sys.Toast.showing || pill.opacity > 0.001
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:toast"
    WlrLayershell.layer: WlrLayer.Overlay

    Ui.Surface {
        id: pill

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        width: parent.width
        height: 44
        radius: height / 2
        elevation: 26

        opacity: Sys.Toast.showing ? 1 : 0
        y: Sys.Toast.showing ? parent.height - height : parent.height

        Behavior on opacity {
            Ui.Anim {
                duration: Motion.quick
            }
        }
        Behavior on y {
            Ui.Anim {
                duration: Motion.settled
                easing.bezierCurve: Sys.Toast.showing ? Motion.enter : Motion.exit
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: Sys.Toast.dismiss()
        }

        Row {
            id: body
            anchors.centerIn: parent
            spacing: Metrics.s3

            Ui.Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: Sys.Toast.level === "error" ? "circle-x" : Sys.Toast.level === "warning" ? "alert-triangle" : "info-circle"
                color: Sys.Toast.level === "error" ? Theme.critical : Sys.Toast.level === "warning" ? Theme.caution : Theme.textSecondary
            }

            Ui.Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Sys.Toast.message
                role: "body"
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 480)
            }
        }
    }
}
