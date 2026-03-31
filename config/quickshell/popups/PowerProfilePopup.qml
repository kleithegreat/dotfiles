import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../components" as Components

FocusScope {
    id: ppPop
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: ppContentLoader.item
    readonly property Item focusTarget: ppPop
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    /*
    Legacy per-popup PanelWindow wrapper retained during the overlay-host migration:
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:powerprofile"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: ppPop.close()
        MouseArea { anchors.fill: parent; onClicked: ppPop.close() }
    }
    */

    property real batPct: {
        let r = UPower.displayDevice.percentage;
        return (r <= 1.0 && r > 0) ? r * 100 : r;
    }
    property bool charging: UPower.displayDevice.state === UPowerDeviceState.Charging || UPower.displayDevice.state === UPowerDeviceState.FullyCharged

    function preparePanelForOpen() {
        let item = ppContentLoader.item;
        if (!item)
            return false;

        item.opacity = 0;
        item.scale = 0.92;
        return true;
    }

    onActiveChanged: {
        if (active) {
            forceActiveFocus();
            contentLoaded = true;
            PowerProfileService.detect();
            PowerProfileService.detectChargeLimit();
            if (preparePanelForOpen())
                ppOpenAnim.start();
        }
        else if (!closing) {
            if (ppContentLoader.item) {
                closing = true;
                ppCloseAnim.start();
            } else {
                closing = false;
            }
        }
    }

    Keys.onEscapePressed: ppPop.close()

    SequentialAnimation {
        id: ppOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: ppContentLoader.item
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            Components.Anim {
                target: ppContentLoader.item
                property: "scale"
                to: 1.0
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
        }
    }
    SequentialAnimation {
        id: ppCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: ppContentLoader.item
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: ppContentLoader.item
                property: "scale"
                to: 0.92
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { ppPop.closing = false; } }
    }

    Loader {
        id: ppContentLoader
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: 260
        height: item ? item.implicitHeight : 0
        active: ppPop.contentLoaded || ppPop.active || ppPop.closing
        asynchronous: true
        sourceComponent: ppPanelComponent

        onLoaded: {
            item.opacity = 0;
            item.scale = 0.92;
            if (ppPop.active)
                ppOpenAnim.start();
        }
    }

    Component {
        id: ppPanelComponent

        Rectangle {
            id: ppPanel
            anchors.fill: parent
            implicitHeight: ppCol.implicitHeight + Theme.popupPadding * 2
            radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
            opacity: 0; scale: 0.92
            transformOrigin: Item.TopRight
            Behavior on height {
                Components.Anim {
                    duration: Theme.animHeightResize
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveStandard
                }
            }
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
                    property bool isCur: PowerProfileService.currentProfile === modelData.name
                    property bool isPending: PowerProfileService.pendingProfile === modelData.name && !isCur
                    color: "transparent"

                    // Selection highlight with animated transition
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius
                        color: ppBtn.isCur ? Theme.bg2 : Theme.bg2
                        opacity: ppBtn.isCur ? 0.8 : (ppBtn.isPending ? 0.5 : (ppBtnA.pressed ? 0.9 : (ppBtnA.containsMouse ? 0.6 : 0)))
                        Behavior on opacity {
                            Components.Anim {
                                duration: Theme.animSpring
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveStandard
                            }
                        }
                    }

                    // Pulsing border while profile switch is in progress
                    Rectangle {
                        id: pendingIndicator
                        anchors.fill: parent; radius: parent.radius
                        color: "transparent"; border.width: 1; border.color: Theme.blueBright
                        visible: ppBtn.isPending; opacity: 0
                        SequentialAnimation {
                            running: ppBtn.isPending; loops: Animation.Infinite
                            NumberAnimation { target: pendingIndicator; property: "opacity"; to: 1.0; duration: 600; easing.type: Easing.InOutCubic }
                            NumberAnimation { target: pendingIndicator; property: "opacity"; to: 0.3; duration: 600; easing.type: Easing.InOutCubic }
                        }
                    }

                    // Animated selection border
                    border.width: ppBtn.isCur ? 1 : 0; border.color: Theme.blueBright
                    Behavior on border.width {
                        Components.Anim {
                            duration: Theme.animSpring
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }

                    Components.HoverLayer {
                        id: ppBtnA
                        hoverOpacity: 0
                        pressedOpacity: 0
                        pressedScale: 0.98
                        onClicked: PowerProfileService.setProfile(ppBtn.modelData.name)

                        RowLayout { anchors.fill: parent; anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: Theme.listItemPadding; spacing: 8
                            Text { text: ppBtn.modelData.icon
                                color: (ppBtn.isCur || ppBtn.isPending) ? Theme.blueBright : Theme.fg
                                Behavior on color {
                                    Components.CAnim {
                                        duration: Theme.animSpring
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                                font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
                            ColumnLayout { spacing: 0; Layout.fillWidth: true
                                Text { text: ppBtn.modelData.label; color: (ppBtn.isCur || ppBtn.isPending) ? Theme.fg : Theme.fg2; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: ppBtn.isCur }
                                Text { text: ppBtn.modelData.desc; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }
            Text {
                text: "Battery: " + Math.round(ppPop.batPct) + "%" + (ppPop.charging ? " (Charging)" : " (Discharging)")
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            }
            Text { visible: PowerProfileService.backend === "autocpufreq"; text: "Using auto-cpufreq (pkexec for changes)"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "Battery Charge Cap"
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: PowerProfileService.chargeLimitStateText
                        color: PowerProfileService.chargeLimitError !== "" ? Theme.redBright : (PowerProfileService.chargeLimitEnabled ? Theme.fg3 : Theme.fg4)
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Components.ToggleSwitch {
                        checked: PowerProfileService.chargeLimitEnabled
                        opacity: PowerProfileService.chargeLimitBusy ? 0.65 : 1.0
                        onToggled: PowerProfileService.setChargeLimit(!PowerProfileService.chargeLimitEnabled)
                    }
                }

                Text {
                    text: PowerProfileService.chargeLimitDetailText
                    color: PowerProfileService.chargeLimitError !== "" ? Theme.redBright : Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall - 1
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }
            }
            }
        }
    }
}
