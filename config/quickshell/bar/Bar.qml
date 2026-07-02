import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: bar

    component VDivider: Rectangle { width: 1; height: Theme.barHeight * 0.4; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }

    property QtObject popupVisibility: null
    property bool doNotDisturb: false
    property int historyCount: 0
    readonly property var brightnessDevices: BrightnessService.devicesForMonitors(DisplayService.monitors, BrightnessService.brightnessDevices)
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
        ExpoButton {}
        VDivider { visible: mpris.visible }
        Mpris { id: mpris; onLabelClicked: bar.popupVisibility?.toggleMpris() }
    }

    Clock {
        anchors.centerIn: parent
        onClicked: bar.popupVisibility?.toggleCalendar()
    }

    RowLayout {
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: Theme.barPadding; spacing: Theme.barSpacing

        TrayExpand { onClicked: bar.popupVisibility?.toggleTray() }

        Rectangle {
            color: Theme.bg1
            radius: Theme.barRadius
            implicitWidth: statusRow.implicitWidth + Theme.barSpacing * 2
            implicitHeight: statusRow.implicitHeight + Theme.barSpacing
            Layout.alignment: Qt.AlignVCenter

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: bar.popupVisibility?.toggleQuickSettings()
            }

            RowLayout {
                id: statusRow
                anchors.centerIn: parent
                spacing: Theme.barSpacing

                Network { onClicked: bar.popupVisibility?.toggleQuickSettings() }
                Bluetooth { onClicked: bar.popupVisibility?.toggleQuickSettings() }
                Volume { onClicked: bar.popupVisibility?.toggleQuickSettings() }
                Brightness { visible: bar.brightnessDevices.length > 0; onClicked: bar.popupVisibility?.toggleQuickSettings() }
                Battery { onClicked: bar.popupVisibility?.toggleQuickSettings() }
            }
        }

        VDivider {}
        Bell {
            doNotDisturb: bar.doNotDisturb
            historyCount: bar.historyCount
            onClicked: bar.popupVisibility?.toggleDrawer()
        }

        VDivider {}
        Power { onClicked: bar.popupVisibility?.togglePowerMenu() }
    }
}
