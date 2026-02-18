import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: drawer
    property bool active: false; signal close()
    property alias model: historyList.model
    property bool doNotDisturb: false
    signal toggleDnd(); signal clearAll(); signal removeItem(int nid)

    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:drawer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: "transparent"; focus: true; Keys.onEscapePressed: drawer.close()
        MouseArea { anchors.fill: parent; onClicked: drawer.close() }
    }

    Rectangle {
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.drawerWidth; height: Math.min(drawerCol.implicitHeight + Theme.notifPadding * 2, 480)
        radius: Theme.notifRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: drawerCol; anchors.fill: parent; anchors.margins: Theme.notifPadding; spacing: 8
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text { text: "Notifications"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; Layout.fillWidth: true }
                Text { text: drawer.doNotDisturb ? "󰂛" : "󰂚"
                    color: dndA.containsMouse ? Theme.yellowBright : (drawer.doNotDisturb ? Theme.orangeBright : Theme.fg4)
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    MouseArea { id: dndA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: drawer.toggleDnd() } }
                Text { text: "Clear"; color: clrA.containsMouse ? Theme.redBright : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; visible: historyList.count > 0
                    MouseArea { id: clrA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: drawer.clearAll() } }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }
            Flickable {
                Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 40; Layout.maximumHeight: 400
                contentHeight: histCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds
                Column { id: histCol; width: parent.width; spacing: Theme.notifSpacing
                    Repeater { id: historyList
                        Rectangle {
                            id: hc; required property string appName; required property string summary; required property string body; required property int nid
                            width: histCol.width; height: hcC.implicitHeight + Theme.notifPadding; radius: 6; color: Theme.bg2
                            ColumnLayout { id: hcC; spacing: 2
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.notifPadding / 2 }
                                RowLayout { Layout.fillWidth: true
                                    Text { text: hc.appName; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: "󰅖"; color: hxA.containsMouse ? Theme.redBright : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                        MouseArea { id: hxA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: drawer.removeItem(hc.nid) } }
                                }
                                Text { text: hc.summary; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text !== "" }
                                Text { text: hc.body; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                            }
                        }
                    }
                }
            }
            Text { visible: historyList.count === 0; text: "No notifications"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter; Layout.topMargin: 20; Layout.bottomMargin: 20 }
        }
    }
}
