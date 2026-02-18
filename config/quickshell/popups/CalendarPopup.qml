import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: cal
    property bool active: false; signal close()
    visible: active
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()

    function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); }
    function firstDow(y, m) { let d = new Date(y, m, 1).getDay(); return d === 0 ? 6 : d - 1; }
    function prevMonth() { if (viewMonth === 0) { viewMonth = 11; viewYear--; } else viewMonth--; }
    function nextMonth() { if (viewMonth === 11) { viewMonth = 0; viewYear++; } else viewMonth++; }

    // Backdrop
    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: cal.close()
        MouseArea { anchors.fill: parent; onClicked: cal.close() }
    }

    // Panel
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: Theme.popupTopMargin
        width: Theme.calWidth; height: calCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: calCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "󰅁"; color: navL.containsMouse ? Theme.fg : Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    MouseArea { id: navL; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: cal.prevMonth() }
                }
                Text {
                    text: ["January","February","March","April","May","June","July","August","September","October","November","December"][cal.viewMonth] + " " + cal.viewYear
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                }
                Text {
                    text: "󰅂"; color: navR.containsMouse ? Theme.fg : Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    MouseArea { id: navR; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: cal.nextMonth() }
                }
            }

            RowLayout { spacing: 0; Layout.fillWidth: true
                Repeater { model: ["Mo","Tu","We","Th","Fr","Sa","Su"]
                    Text { required property string modelData; text: modelData; color: Theme.fg4
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.preferredWidth: Theme.calCellSize; horizontalAlignment: Text.AlignHCenter }
                }
            }

            Grid {
                columns: 7; Layout.fillWidth: true; spacing: 0
                Repeater {
                    model: 42
                    Item {
                        required property int index
                        property int dayNum: index - cal.firstDow(cal.viewYear, cal.viewMonth) + 1
                        property bool isCur: dayNum >= 1 && dayNum <= cal.daysInMonth(cal.viewYear, cal.viewMonth)
                        property bool isToday: {
                            let n = new Date();
                            return isCur && dayNum === n.getDate() && cal.viewMonth === n.getMonth() && cal.viewYear === n.getFullYear();
                        }
                        width: Theme.calCellSize; height: Theme.calCellSize

                        Rectangle {
                            anchors.centerIn: parent; width: 26; height: 26; radius: 13
                            color: isToday ? Theme.blueBright : "transparent"
                        }
                        Text {
                            anchors.centerIn: parent; text: isCur ? dayNum : ""
                            color: isToday ? Theme.bg : ((index % 7 >= 5) ? Theme.fg4 : Theme.fg)
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: isToday
                        }
                    }
                }
            }

            Text {
                text: Qt.formatDateTime(new Date(), "dddd, MMMM d, yyyy  h:mm AP")
                color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.alignment: Qt.AlignHCenter
            }
        }
    }
}
