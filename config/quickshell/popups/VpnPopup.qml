import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "../components" as Components

FocusScope {
    id: vpnPop
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: vpnContentLoader.item
    readonly property Item focusTarget: vpnPop
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    function preparePanelForOpen() {
        let item = vpnContentLoader.item;
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
            VpnService.refresh();
            if (preparePanelForOpen())
                vpnOpenAnim.start();
        } else if (!closing) {
            if (vpnContentLoader.item) {
                closing = true;
                vpnCloseAnim.start();
            } else {
                closing = false;
            }
        }
    }

    SequentialAnimation {
        id: vpnOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: vpnContentLoader.item
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            Components.Anim {
                target: vpnContentLoader.item
                property: "scale"
                to: 1.0
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
        }
    }
    SequentialAnimation {
        id: vpnCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: vpnContentLoader.item
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: vpnContentLoader.item
                property: "scale"
                to: 0.92
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { vpnPop.closing = false; } }
    }

    readonly property bool mullvadOn: VpnService.mullvadState === "connected" || VpnService.mullvadState === "connecting"
    readonly property bool tailscaleOn: VpnService.tailscaleState === "running" || VpnService.tailscaleState === "starting"

    readonly property string mullvadStatus: {
        let s = VpnService.mullvadState;
        if (s === "connected") {
            let loc = VpnService.mullvadCity || VpnService.mullvadCountry;
            return loc ? "Connected — " + loc : "Connected";
        }
        if (s === "connecting") return "Connecting…";
        if (s === "disconnecting") return "Disconnecting…";
        if (s === "error") return "Error";
        return "Disconnected";
    }

    readonly property string tailscaleStatus: {
        let s = VpnService.tailscaleState;
        if (s === "running") return "Running";
        if (s === "starting") return "Starting…";
        if (s === "needs-login") return "Needs Login";
        return "Stopped";
    }

    Keys.onEscapePressed: vpnPop.close()

    Loader {
        id: vpnContentLoader
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.popupWidth
        height: item ? item.implicitHeight : 0
        active: vpnPop.contentLoaded || vpnPop.active || vpnPop.closing
        asynchronous: true
        sourceComponent: vpnPanelComponent

        onLoaded: {
            item.opacity = 0;
            item.scale = 0.92;
            if (vpnPop.active)
                vpnOpenAnim.start();
        }
    }

    Component {
        id: vpnPanelComponent

        Rectangle {
            id: vpnPanel
            anchors.fill: parent
            implicitHeight: vpnCol.implicitHeight + Theme.popupPadding * 2
            radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
            opacity: 0; scale: 0.92
            transformOrigin: Item.TopRight
            Behavior on implicitHeight {
                Components.Anim {
                    duration: Theme.animHeightResize
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveStandard
                }
            }
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: vpnCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: Theme.listItemPadding

            // ── Mullvad ──
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text { text: "󰒃  Mullvad"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
                Text {
                    text: vpnPop.mullvadStatus
                    color: VpnService.mullvadState === "connected" ? Theme.fg3
                         : VpnService.mullvadState === "error" ? Theme.redBright
                         : Theme.fg4
                    Behavior on color {
                        Components.CAnim {
                            duration: Theme.animHover
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                }
                Components.ToggleSwitch {
                    checked: vpnPop.mullvadOn
                    onToggled: vpnPop.mullvadOn ? VpnService.mullvadDisconnect() : VpnService.mullvadConnect()
                }
            }
            Text {
                visible: VpnService.mullvadState === "connected" && VpnService.mullvadIp
                text: VpnService.mullvadIp
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight; Layout.fillWidth: true
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            // ── Tailscale ──
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text { text: "󰛳  Tailscale"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
                Text {
                    text: vpnPop.tailscaleStatus
                    color: VpnService.tailscaleState === "running" ? Theme.fg3
                         : VpnService.tailscaleState === "needs-login" ? Theme.yellowBright
                         : Theme.fg4
                    Behavior on color {
                        Components.CAnim {
                            duration: Theme.animHover
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                }
                Components.ToggleSwitch {
                    checked: vpnPop.tailscaleOn
                    onToggled: vpnPop.tailscaleOn ? VpnService.tailscaleDown() : VpnService.tailscaleUp()
                }
            }
            Text {
                visible: VpnService.tailscaleState === "running" && (VpnService.tailscaleTailnet || VpnService.tailscaleIp)
                text: {
                    let parts = [];
                    if (VpnService.tailscaleTailnet) parts.push(VpnService.tailscaleTailnet);
                    if (VpnService.tailscaleIp) parts.push(VpnService.tailscaleIp);
                    if (VpnService.tailscaleExitNode) parts.push("Exit Node");
                    return parts.join(" · ");
                }
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight; Layout.fillWidth: true
            }
            }
        }
    }
}
