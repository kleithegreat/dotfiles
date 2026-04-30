import qs
import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import "../components" as Components

FocusScope {
    id: trayPop
    property bool active: false; signal close()
    property bool closing: false
    readonly property bool hasItems: SystemTray.items.values.length > 0
    readonly property bool overlayVisible: (active || closing) && hasItems
    readonly property Item panelItem: trayPanel
    readonly property Item focusTarget: trayPop
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    onActiveChanged: {
        if (active) {
            if (!hasItems) {
                close();
                return;
            }
            trayCloseAnim.stop();
            closing = false;
            forceActiveFocus();
            trayPanel.opacity = 0;
            trayPanel.scale = Theme.popupStartScale;
            trayOpenAnim.restart();
        }
        else if (!closing) { trayOpenAnim.stop(); closing = true; TooltipService.hide(); trayCloseAnim.restart(); }
    }
    onHasItemsChanged: {
        if (!hasItems && active)
            close();
    }
    Keys.onEscapePressed: trayPop.close()

    SequentialAnimation {
        id: trayOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: trayPanel
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            SequentialAnimation {
                PauseAnimation { duration: Theme.animPopupScaleLead }
                Components.Anim {
                    target: trayPanel
                    property: "scale"
                    to: 1.0
                    duration: Math.max(0, Theme.animPopupIn - Theme.animPopupScaleLead)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveEmphasizedEnter
                }
            }
        }
    }
    SequentialAnimation {
        id: trayCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: trayPanel
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: trayPanel
                property: "scale"
                to: Theme.popupStartScale
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { trayPop.closing = false; } }
    }

    Rectangle {
        id: trayPanel
        anchors.right: parent.right; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut + 140
        width: trayGrid.implicitWidth + Theme.barPadding * 2
        height: trayGrid.implicitHeight + Theme.barPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        opacity: 0; scale: Theme.popupStartScale
        transformOrigin: Item.TopRight
        layer.enabled: trayOpenAnim.running || trayCloseAnim.running
        layer.smooth: true
        y: trayPop.active ? anchors.topMargin : anchors.topMargin - 12
        Behavior on y {
            Components.Anim {
                duration: trayPop.active ? Theme.animPopupIn : Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: trayPop.active ? Theme.animCurveEmphasizedEnter : Theme.animCurveExit
            }
        }

        Grid {
            id: trayGrid; anchors.centerIn: parent; columns: Math.min(4, SystemTray.items.values.length); spacing: Theme.barSpacing
            Repeater {
                model: SystemTray.items
                Item {
                    id: trayItem; required property var modelData; required property int index
                    width: Theme.iconSize + 4; height: Theme.iconSize + 4

                    // ── Staggered entrance animation ──
                    opacity: 0
                    scale: Theme.popupStartScale
                    Component.onCompleted: {
                        staggerAnim.delay = index * Theme.animStagger;
                        staggerAnim.start();
                    }
                    SequentialAnimation {
                        id: staggerAnim
                        property int delay: 0
                        PauseAnimation { duration: staggerAnim.delay }
                        ParallelAnimation {
                            Components.Anim {
                                target: trayItem
                                property: "opacity"
                                to: 1
                                duration: Theme.animNormal
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveEnter
                            }
                            Components.Anim {
                                target: trayItem
                                property: "scale"
                                to: 1.0
                                duration: Theme.animMedium
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveEmphasizedEnter
                            }
                        }
                    }

                    Components.HoverLayer {
                        id: trayMouseArea
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        color: Theme.bg2
                        hoverOpacity: 0.7
                        pressedOpacity: 0.9
                        pressedScale: 0.9
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.LeftButton) trayItem.modelData.activate();
                            else trayItem.modelData.secondaryActivate();
                        }
                        onContainsMouseChanged: {
                            if (containsMouse) {
                                let text = trayItem.modelData.tooltipTitle || trayItem.modelData.title || trayItem.modelData.id || "";
                                if (text) {
                                    let p = trayItem.mapToGlobal(Qt.point(trayItem.width / 2, trayItem.height));
                                    TooltipService.show(text, p.x, p.y);
                                }
                            } else {
                                TooltipService.hide();
                            }
                        }

                        Image {
                            id: trayImg; anchors.centerIn: parent
                            width: Theme.iconSize; height: Theme.iconSize
                            source: Quickshell.iconPath(trayItem.modelData.id ?? "", true) || (trayItem.modelData.icon ?? "")
                            sourceSize.width: Theme.iconSize * 2; sourceSize.height: Theme.iconSize * 2
                            smooth: true; fillMode: Image.PreserveAspectFit
                            cache: false
                            visible: status === Image.Ready
                        }

                        Components.Icon {
                            anchors.centerIn: parent
                            visible: !trayImg.visible && (trayItem.modelData.id ?? trayItem.modelData.title ?? "").toLowerCase().includes("spotify")
                            source: "../icons/brand-spotify.svg"
                            color: Theme.fg3
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !trayImg.visible && !(trayItem.modelData.id ?? trayItem.modelData.title ?? "").toLowerCase().includes("spotify")
                            text: {
                                let id = (trayItem.modelData.id ?? trayItem.modelData.title ?? "").toLowerCase();
                                return id.length > 0 ? id.charAt(0).toUpperCase() : "?";
                            }
                            color: Theme.fg3
                            font.family: Theme.monoFamily; font.pixelSize: Theme.iconSize; font.bold: true
                        }
                    }
                }
            }
        }
    }
}
