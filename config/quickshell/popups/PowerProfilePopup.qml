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
    property bool closing: false
    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:powerprofile"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property string currentProfile: "unknown"
    property string backend: "none"

    onActiveChanged: {
        if (active) { detect(); ppOpenAnim.start(); }
        else { closing = true; ppCloseAnim.start(); }
    }

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

    SequentialAnimation {
        id: ppOpenAnim
        ParallelAnimation {
            NumberAnimation { target: ppPanel; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: ppPanel; property: "scale"; to: 1.0; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: ppCloseAnim
        ParallelAnimation {
            NumberAnimation { target: ppPanel; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
            NumberAnimation { target: ppPanel; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { ppPop.closing = false; } }
    }

    Rectangle {
        id: ppPanel
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: 260; height: ppCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: 0.92
        transformOrigin: Item.TopRight
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: ppCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 8

            Text { text: "⚡ Power Profile"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            Repeater {
                model: [
                    { name: "performance", label: "Performance", icon: "󰵣", desc: "Max speed, more heat" },
                    { name: "balanced",    label: "Balanced",    icon: "󰓅", desc: "Auto / default" },
                    { name: "power-saver", label: "Power Saver", icon: "󰸲",  desc: "Extend battery life" }
                ]
                Rectangle {
                    id: ppBtn; required property var modelData; required property int index
                    Layout.fillWidth: true; height: 38; radius: Theme.hoverRadius
                    property bool isCur: ppPop.currentProfile === modelData.name
                    color: "transparent"

                    // Selection highlight with animated transition
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius
                        color: ppBtn.isCur ? Theme.bg2 : Theme.bg2
                        opacity: ppBtn.isCur ? 0.8 : (ppBtnA.pressed ? 0.9 : (ppBtnA.containsMouse ? 0.6 : 0))
                        Behavior on opacity { NumberAnimation { duration: Theme.animSpring; easing.type: Easing.OutCubic } }
                    }

                    // Animated selection border
                    border.width: ppBtn.isCur ? 1 : 0; border.color: Theme.blueBright
                    Behavior on border.width { NumberAnimation { duration: Theme.animSpring; easing.type: Easing.OutCubic } }

                    scale: ppBtnA.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center

                    RowLayout { anchors.fill: parent; anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: Theme.listItemPadding; spacing: 8
                        Text { text: ppBtn.modelData.icon
                            color: ppBtn.isCur ? Theme.blueBright : Theme.fg
                            Behavior on color { ColorAnimation { duration: Theme.animSpring } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
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
