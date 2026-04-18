import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "components" as Components

FocusScope {
    id: powerMenu
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: powerMenuContentLoader.item
    readonly property Item focusTarget: powerMenu
    readonly property bool scrimEnabled: true
    readonly property color scrimColor: Theme.bg0_h
    readonly property real scrimOpacity: 0.72
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    onActiveChanged: {
        if (active) {
            forceActiveFocus();
            contentLoaded = true;
        } else if (!closing) {
            closing = true; pwrCloseTimer.start();
        }
    }
    Timer { id: pwrCloseTimer; interval: Theme.animPopupOut; onTriggered: powerMenu.closing = false }

    Timer {
        interval: 1200
        running: !powerMenu.contentLoaded
        repeat: false
        onTriggered: powerMenu.contentLoaded = true
    }

    Keys.onEscapePressed: powerMenu.close()

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
                    { icon: "../icons/lock.svg",    label: "Lock",     cmd: "loginctl lock-session" },
                    { icon: "../icons/zzz.svg",     label: "Suspend",  cmd: "systemctl suspend" },
                    { icon: "../icons/refresh.svg", label: "Reboot",   cmd: "systemctl reboot" },
                    { icon: "../icons/power.svg",   label: "Shutdown", cmd: "systemctl poweroff" }
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
                    scale: Theme.popupStartScale
                    Component.onCompleted: { pwrEnterAnim.start(); }
                    SequentialAnimation {
                        id: pwrEnterAnim
                        PauseAnimation { duration: pwrBtn.index * Theme.animStagger }
                        ParallelAnimation {
                            Components.Anim {
                                target: pwrBtn
                                property: "opacity"
                                to: 1
                                duration: Theme.animMedium
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveEmphasizedEnter
                            }
                            Components.Anim {
                                target: pwrBtn
                                property: "scale"
                                to: 1.0
                                duration: Theme.animPopupIn
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
                            Components.Icon { source: pwrBtn.modelData.icon
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
                                iconSize: Theme.powerIconSize; Layout.alignment: Qt.AlignHCenter }
                            Text { text: pwrBtn.modelData.label; color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }
                        }
                    }
                }
            }
        }
    }
    Process { id: pwrProc; running: false }
}
