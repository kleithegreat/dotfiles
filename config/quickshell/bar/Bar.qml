import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: bar
    property var shellRoot: null
    anchors { top: true; left: true; right: true }
    margins { top: Theme.barMargin; left: Theme.barMargin; right: Theme.barMargin }
    implicitHeight: Theme.barHeight
    color: "transparent"
    WlrLayershell.namespace: "quickshell:bar"

    Rectangle { anchors.fill: parent; color: Theme.bg; opacity: Theme.barOpacity; radius: Theme.barRadius }

    RowLayout {
        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Theme.barPadding; spacing: Theme.barSpacing
        Workspaces {}
        Rectangle { visible: mpris.visible; width: 1; height: Theme.barHeight * 0.4; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
        Mpris { id: mpris; onLabelClicked: { if (bar.shellRoot) bar.shellRoot.openPopup("mpris"); } }
    }

    Clock {
        anchors.centerIn: parent
        onClicked: { if (bar.shellRoot) bar.shellRoot.openPopup("calendar"); }
    }

    RowLayout {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Theme.barPadding; spacing: Theme.barSpacing

        Network { onClicked: { if (bar.shellRoot) bar.shellRoot.openPopup("wifi"); } }
        Volume { onClicked: { if (bar.shellRoot) bar.shellRoot.openPopup("audio"); } }
        Battery { onClicked: { if (bar.shellRoot) bar.shellRoot.openPopup("powerprofile"); } }

        Bell {
            doNotDisturb: bar.shellRoot?.doNotDisturb ?? false
            historyCount: bar.shellRoot?.historyCount ?? 0
            onClicked: { if (bar.shellRoot) bar.shellRoot.openPopup("drawer"); }
        }

        TrayExpand { onClicked: { if (bar.shellRoot) bar.shellRoot.openPopup("tray"); } }

        Rectangle { width: 1; height: Theme.barHeight * 0.4; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
        Power { onClicked: { if (bar.shellRoot) bar.shellRoot.openPopup("powermenu"); } }
    }
}
