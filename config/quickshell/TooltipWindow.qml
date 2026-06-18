import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Window
import "components" as Components

PanelWindow {
    anchors { top: true; left: true }
    margins {
        top: Theme.barHeight + Theme.barMargin + 4
        left: Math.max(
            Theme.gapOut,
            Math.min(
                TooltipService.targetX - tooltipRect.width / 2,
                Screen.width - tooltipRect.width - Theme.gapOut
            )
        )
    }
    implicitWidth: tooltipRect.width
    implicitHeight: tooltipRect.height
    visible: TooltipService.visible || tooltipRect.opacity > 0.001
    color: "transparent"
    mask: Region {}
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:tooltip"
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        id: tooltipRect
        readonly property real maxWidth: Math.min(Math.max(Theme.fontSize * 20, 180), Screen.width - Theme.gapOut * 2)
        width: Math.min(tooltipLabel.implicitWidth + Theme.barPadding, maxWidth)
        height: tooltipLabel.implicitHeight + Theme.barSpacing
        radius: Theme.btnRadius
        color: Theme.bg1
        border.width: 1
        border.color: Theme.bg3
        opacity: TooltipService.visible ? 1.0 : 0.0
        scale: TooltipService.visible ? 1.0 : 0.95

        Behavior on opacity {
            Components.Anim { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            Components.Anim { duration: Theme.animFast; easing.type: Easing.OutCubic }
        }

        Text {
            id: tooltipLabel
            anchors.fill: parent
            anchors.margins: Theme.barPadding / 2
            text: TooltipService.text
            color: Theme.fg
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
