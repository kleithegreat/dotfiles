import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "components" as Components

PanelWindow {
    id: drawer
    property bool active: false; signal close()
    property bool closing: false
    property alias model: historyList.model
    property bool doNotDisturb: false
    signal toggleDnd(); signal clearAll(); signal removeItem(int nid)

    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:drawer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: "transparent"; focus: true; Keys.onEscapePressed: drawer.close()
        MouseArea { anchors.fill: parent; onClicked: drawer.close() }
    }

    onActiveChanged: {
        if (active) { drawerPanel.opacity = 0; drawerPanel.scale = 0.92; drawerOpenAnim.start(); }
        else if (!closing) { closing = true; drawerCloseAnim.start(); }
    }

    SequentialAnimation {
        id: drawerOpenAnim
        ParallelAnimation {
            NumberAnimation { target: drawerPanel; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: drawerPanel; property: "scale"; to: 1.0; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: drawerCloseAnim
        ParallelAnimation {
            NumberAnimation { target: drawerPanel; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
            NumberAnimation { target: drawerPanel; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { drawer.closing = false; } }
    }

    Rectangle {
        id: drawerPanel
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.drawerWidth; height: Math.min(drawerCol.implicitHeight + Theme.notifPadding * 2, 480)
        radius: Theme.notifRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: 0.92
        transformOrigin: Item.TopRight
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: drawerCol; anchors.fill: parent; anchors.margins: Theme.notifPadding; spacing: 8
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text { text: "󰂚  Notifications"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }

                // DnD toggle using unified component
                RowLayout { spacing: 4
                    Text { text: drawer.doNotDisturb ? "󰂛" : "󰂚"
                        color: drawer.doNotDisturb ? Theme.orangeBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize }
                    Components.ToggleSwitch {
                        checked: drawer.doNotDisturb
                        onToggled: drawer.toggleDnd()
                    }
                }

                // Clear button
                Rectangle {
                    visible: historyList.count > 0
                    width: clrLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: clrA.pressed ? 0.9 : (clrA.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: clrA.pressed ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text { id: clrLabel; anchors.centerIn: parent; text: "Clear"
                        color: clrA.containsMouse ? Theme.redBright : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    MouseArea { id: clrA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: drawer.clearAll() }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 40; Layout.maximumHeight: 400
                contentHeight: histCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column { id: histCol; width: parent.width; spacing: Theme.notifSpacing
                    Repeater { id: historyList
                        Rectangle {
                            id: hc; required property string appName; required property string summary; required property string body; required property int nid; required property int index
                            width: histCol.width; height: hcC.implicitHeight + Theme.notifPadding; radius: Theme.btnRadius; color: Theme.bg2

                            // Staggered fade+slide entrance
                            opacity: 0; y: 8
                            Component.onCompleted: { hcEnterAnim.delay = index * Theme.animStagger; hcEnterAnim.start(); }
                            SequentialAnimation {
                                id: hcEnterAnim; property int delay: 0
                                PauseAnimation { duration: hcEnterAnim.delay }
                                ParallelAnimation {
                                    NumberAnimation { target: hc; property: "opacity"; to: 1; duration: Theme.animContentSwap; easing.type: Easing.OutCubic }
                                    NumberAnimation { target: hc; property: "y"; to: 0; duration: Theme.animContentSwap; easing.type: Easing.OutCubic }
                                }
                            }

                            ColumnLayout { id: hcC; spacing: 2
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.notifPadding / 2 }
                                RowLayout { Layout.fillWidth: true
                                    Text { text: hc.appName; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Rectangle {
                                        width: 18; height: 18; radius: Theme.hoverRadius; color: "transparent"
                                        Rectangle {
                                            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                                            opacity: hxA.pressed ? 0.9 : (hxA.containsMouse ? 0.6 : 0)
                                            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                                        }
                                        scale: hxA.pressed ? 0.9 : 1.0
                                        Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                                        transformOrigin: Item.Center
                                        Text { anchors.centerIn: parent; text: "󰅖"
                                            color: hxA.containsMouse ? Theme.redBright : Theme.fg4
                                            Behavior on color { ColorAnimation { duration: Theme.animHover } }
                                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                                        MouseArea { id: hxA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: drawer.removeItem(hc.nid) }
                                    }
                                }
                                Text { text: hc.summary; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text !== "" }
                                Text { text: hc.body; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                            }
                        }
                    }
                }
            }
            // Empty state with icon
            ColumnLayout {
                visible: historyList.count === 0; Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter; spacing: 4
                Layout.topMargin: 20; Layout.bottomMargin: 20
                Text { text: "󰂚"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: 24; Layout.alignment: Qt.AlignHCenter }
                Text { text: "No notifications"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }
            }
        }
    }
}
