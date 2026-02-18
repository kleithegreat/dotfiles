import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
PanelWindow {
    id: bar
    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: Theme.barMargin
        left: Theme.barMargin
        right: Theme.barMargin
    }
    implicitHeight: Theme.barHeight
    color: "transparent"
    WlrLayershell.namespace: "quickshell:bar"
    Rectangle {
        anchors.fill: parent
        color: Theme.bg
        opacity: Theme.barOpacity
        radius: Theme.barRadius
    }
    RowLayout {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.barPadding
        spacing: Theme.barSpacing
        Workspaces {}
    }
    Clock {
        anchors.centerIn: parent
    }
    RowLayout {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Theme.barPadding
        spacing: Theme.barSpacing
        Network {}
        Volume {}
        Battery {}
        Tray {}
    }
}