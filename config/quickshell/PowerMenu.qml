import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "components" as Components

PanelWindow {
    id: powerMenu
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    visible: active || closing

    onActiveChanged: {
        if (active) {
            contentLoaded = true;
        } else if (!closing) {
            closing = true; pwrCloseTimer.start();
        }
    }
    Timer { id: pwrCloseTimer; interval: Theme.animPopupOut; onTriggered: powerMenu.closing = false }
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:powermenu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: Theme.bg0_h; opacity: powerMenu.active ? 0.72 : 0; focus: true
        Behavior on opacity {
            Components.Anim {
                duration: powerMenu.active ? Theme.animPopupIn : Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: powerMenu.active ? Theme.animCurveEmphasizedEnter : Theme.animCurveExit
            }
        }
        Keys.onEscapePressed: powerMenu.close()
        MouseArea { anchors.fill: parent; onClicked: powerMenu.close() }
    }

    Loader {
        id: powerMenuContentLoader
        anchors.centerIn: parent
        width: item ? item.implicitWidth : 0
        height: item ? item.implicitHeight : 0
        active: powerMenu.contentLoaded || powerMenu.active || powerMenu.closing
        asynchronous: true
        sourceComponent: powerMenuContent
    }

    Component {
        id: powerMenuContent

        RowLayout {
            anchors.fill: parent; spacing: Theme.powerBtnSpacing
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
                    color: "transparent"
                    // Background base
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg1; z: -1
                        border.width: 1; border.color: pwrA.containsMouse ? Theme.fg4 : Theme.bg3
                        Behavior on border.color {
                            Components.CAnim {
                                duration: Theme.animHover
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveStandard
                            }
                        }
                    }

                    opacity: 0
                    scale: 0.92
                    Component.onCompleted: { pwrEnterAnim.start(); }
                    SequentialAnimation {
                        id: pwrEnterAnim
                        PauseAnimation { duration: pwrBtn.index * 50 }
                        ParallelAnimation {
                            Components.Anim {
                                target: pwrBtn
                                property: "opacity"
                                to: 1
                                duration: 300
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveEnter
                            }
                            Components.Anim {
                                target: pwrBtn
                                property: "scale"
                                to: 1.0
                                duration: 400
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveEmphasizedEnter
                            }
                        }
                    }

                    Components.HoverLayer {
                        id: pwrA
                        color: Theme.bg2
                        hoverOpacity: 0.6
                        pressedOpacity: 0.9
                        pressedScale: pwrBtn.index >= 2 ? 0.92 : 0.95
                        onClicked: {
                            powerMenu.close();
                            pwrProc.command = ["sh", "-c", pwrBtn.modelData.cmd];
                            pwrProc.running = true;
                        }

                        ColumnLayout { anchors.centerIn: parent; spacing: 8
                            Text { text: pwrBtn.modelData.icon
                                color: {
                                    if (!pwrA.containsMouse) return Theme.fg;
                                    if (pwrBtn.index === 3) return Theme.redBright;
                                    if (pwrBtn.index === 2) return Theme.orangeBright;
                                    return Theme.yellowBright;
                                }
                                Behavior on color {
                                    Components.CAnim {
                                        duration: Theme.animHover
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Theme.animCurveStandard
                                    }
                                }
                                font.family: Theme.fontFamily; font.pixelSize: Theme.powerIconSize; Layout.alignment: Qt.AlignHCenter }
                            Text { text: pwrBtn.modelData.label; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                }
            }
        }
    }
    Process { id: pwrProc; running: false }
}
