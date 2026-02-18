import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Services.UPower

PanelWindow {
    id: ppPop
    property bool active: false; signal close()
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:powerprofile"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property string currentProfile: "unknown"
    property string backend: "none"

    onActiveChanged: { if (active) detect(); }

    function detect() { ppctlProc.running = true; }

    function setProfile(profile) {
        if (backend === "ppctl") {
            setProc.command = ["powerprofilesctl", "set", profile];
        } else {
            let m = profile === "performance" ? "performance" : (profile === "power-saver" ? "powersave" : "reset");
            if (m === "reset") setProc.command = ["pkexec", "auto-cpufreq", "--force=reset"];
            else setProc.command = ["pkexec", "auto-cpufreq", "--force=" + m];
        }
        setProc.running = true;
        refreshTimer.restart();
    }

    Timer { id: refreshTimer; interval: 1500; onTriggered: detect() }

    Process {
        id: ppctlProc; command: ["powerprofilesctl", "get"]; running: false
        stdout: SplitParser { onRead: (line) => { ppPop.backend = "ppctl"; ppPop.currentProfile = line.trim(); } }
        onExited: (code, status) => { if (code !== 0) { ppPop.backend = "autocpufreq"; govProc.running = true; } }
    }
    Process {
        id: govProc; command: ["cat", "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"]; running: false
        stdout: SplitParser { onRead: (line) => {
            let g = line.trim();
            if (g === "performance") ppPop.currentProfile = "performance";
            else if (g === "powersave") ppPop.currentProfile = "power-saver";
            else ppPop.currentProfile = "balanced";
        } }
    }
    Process { id: setProc; running: false }

    property real batPct: {
        let r = UPower.displayDevice.percentage;
        return (r <= 1.0 && r > 0) ? r * 100 : r;
    }
    property bool charging: UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: ppPop.close()
        MouseArea { anchors.fill: parent; onClicked: ppPop.close() }
    }

    Rectangle {
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut + 50
        width: 260; height: ppCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: ppCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 8

            Text { text: "Power Profile"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            Repeater {
                model: [
                    { name: "performance", label: "Performance", icon: "󰵣", desc: "Max speed, more heat" },
                    { name: "balanced",    label: "Balanced",    icon: "󰓅", desc: "Auto / default" },
                    { name: "power-saver", label: "Power Saver", icon: "󰸲",  desc: "Extend battery life" }
                ]
                Rectangle {
                    id: ppBtn; required property var modelData; required property int index
                    Layout.fillWidth: true; height: 38; radius: 8
                    property bool isCur: ppPop.currentProfile === modelData.name
                    color: isCur ? Theme.bg2 : (ppBtnA.containsMouse ? Theme.bg2 : "transparent")
                    border.width: isCur ? 1 : 0; border.color: Theme.blueBright

                    RowLayout { anchors.fill: parent; anchors.leftMargin: 10; anchors.rightMargin: 10; spacing: 8
                        Text { text: ppBtn.modelData.icon; color: ppBtn.isCur ? Theme.blueBright : Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
                        ColumnLayout { spacing: 0; Layout.fillWidth: true
                            Text { text: ppBtn.modelData.label; color: ppBtn.isCur ? Theme.fg : Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: ppBtn.isCur }
                            Text { text: ppBtn.modelData.desc; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                        }
                    }
                    MouseArea { id: ppBtnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: ppPop.setProfile(ppBtn.modelData.name) }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }
            Text {
                text: "Battery: " + Math.round(ppPop.batPct) + "%" + (ppPop.charging ? " (Charging)" : " (Discharging)")
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
            Text { visible: ppPop.backend === "autocpufreq"; text: "Using auto-cpufreq (pkexec for changes)"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
        }
    }
}
