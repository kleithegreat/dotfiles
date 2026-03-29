import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: bar
    property QtObject popupVisibility: null
    property bool doNotDisturb: false
    property int historyCount: 0
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
        Mpris { id: mpris; onLabelClicked: { if (bar.popupVisibility) bar.popupVisibility.toggleMpris(); } }
    }

    Clock {
        anchors.centerIn: parent
        onClicked: { if (bar.popupVisibility) bar.popupVisibility.toggleCalendar(); }
    }

    RowLayout {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Theme.barPadding; spacing: Theme.barSpacing

        Network { onClicked: { if (bar.popupVisibility) bar.popupVisibility.toggleWifi(); } }
        Bluetooth { onClicked: { if (bar.popupVisibility) bar.popupVisibility.toggleBluetooth(); } }
        Volume { onClicked: { if (bar.popupVisibility) bar.popupVisibility.toggleAudio(); } }
        Battery { onClicked: { if (bar.popupVisibility) bar.popupVisibility.togglePowerProfile(); } }

        Bell {
            doNotDisturb: bar.doNotDisturb
            historyCount: bar.historyCount
            onClicked: { if (bar.popupVisibility) bar.popupVisibility.toggleDrawer(); }
        }

        TrayExpand { onClicked: { if (bar.popupVisibility) bar.popupVisibility.toggleTray(); } }

        Rectangle { width: 1; height: Theme.barHeight * 0.4; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
        Power { onClicked: { if (bar.popupVisibility) bar.popupVisibility.togglePowerMenu(); } }
    }
}
