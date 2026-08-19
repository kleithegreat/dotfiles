import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.ui as Ui

// A menu, not a screen. Losing work to a mis-click is the only real risk here,
// so the two actions that can do it ask once, in place, instead of firing on
// the first press like the neighbouring harmless ones.
Popover {
    id: root

    required property ShellState state

    shown: state.isOpen("session")
    anchor: state.anchor
    panelWidth: 240
    contentHeight: menu.implicitHeight

    readonly property var actions: [
        { id: "lock", label: "Lock", icon: "lock", argv: ["loginctl", "lock-session"], confirm: false },
        { id: "suspend", label: "Sleep", icon: "zzz", argv: ["systemctl", "suspend"], confirm: false },
        { id: "restart", label: "Restart", icon: "refresh", argv: ["systemctl", "reboot"], confirm: true },
        { id: "shutdown", label: "Shut Down", icon: "power", argv: ["systemctl", "poweroff"], confirm: true }
    ]

    property string arming: ""

    onShownChanged: if (!shown) arming = ""

    function invoke(action) {
        if (action.confirm && arming !== action.id) {
            arming = action.id;
            return;
        }
        runner.command = action.argv;
        runner.running = true;
        state.close();
    }

    Process {
        id: runner
    }

    ColumnLayout {
        id: menu
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 2

        Repeater {
            model: root.actions

            Ui.ListRow {
                id: option

                required property var modelData
                readonly property bool arming: root.arming === option.modelData.id

                Layout.fillWidth: true
                icon: option.modelData.icon
                title: arming ? "Confirm " + option.modelData.label.toLowerCase() : option.modelData.label
                iconColor: option.modelData.confirm && (option.arming || option.hovered) ? Theme.critical : Theme.textSecondary
                tint: option.arming ? Theme.withAlpha(Theme.critical, 0.18) : "transparent"
                onClicked: root.invoke(option.modelData)
            }
        }
    }
}
