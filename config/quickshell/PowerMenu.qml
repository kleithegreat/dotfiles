import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io

PanelWindow {
    id: powerMenu
    property bool active: false; signal close()
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:powermenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Theme.bg0_h; opacity: 0.72; focus: true
        Keys.onEscapePressed: powerMenu.close()
        MouseArea { anchors.fill: parent; onClicked: powerMenu.close() }
    }

    RowLayout {
        anchors.centerIn: parent; spacing: Theme.powerBtnSpacing
        Repeater {
            model: [
                { icon: "󰌾",    label: "Lock",     cmd: "loginctl lock-session" },
                { icon: "󰒲",   label: "Suspend",  cmd: "systemctl suspend" },
                { icon: "󰑓", label: "Reboot",   cmd: "systemctl reboot" },
                { icon: "󰐥",   label: "Shutdown", cmd: "systemctl poweroff" }
            ]
            Rectangle {
                id: pwrBtn; required property var modelData; required property int index
                width: Theme.powerBtnSize; height: Theme.powerBtnSize + 24; radius: Theme.powerBtnRadius
                color: pwrA.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1; border.color: pwrA.containsMouse ? Theme.fg4 : Theme.bg3
                Behavior on color { ColorAnimation { duration: 120 } }

                ColumnLayout { anchors.centerIn: parent; spacing: 8
                    Text { text: pwrBtn.modelData.icon
                        color: { if (!pwrA.containsMouse) return Theme.fg; if (pwrBtn.index === 3) return Theme.redBright; if (pwrBtn.index === 2) return Theme.orangeBright; return Theme.yellowBright; }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.powerIconSize; Layout.alignment: Qt.AlignHCenter }
                    Text { text: pwrBtn.modelData.label; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }
                }
                MouseArea { id: pwrA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    onClicked: { powerMenu.close(); pwrProc.command = ["sh", "-c", pwrBtn.modelData.cmd]; pwrProc.running = true; } }
            }
        }
    }
    Process { id: pwrProc; running: false }
}
