import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

PanelWindow {
    id: cal
    property bool active: false; signal close()
    property bool closing: false
    visible: active || closing
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:calendar"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    onActiveChanged: {
        if (active) {
            let today = new Date();
            viewYear = today.getFullYear();
            viewMonth = today.getMonth();
            calPanel.opacity = 0; calPanel.scale = 0.92;
            calOpenAnim.start();
        } else if (!closing) {
            closing = true; calCloseAnim.start();
        }
    }

    SequentialAnimation {
        id: calOpenAnim
        ParallelAnimation {
            NumberAnimation { target: calPanel; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
            NumberAnimation { target: calPanel; property: "scale"; to: 1.0; duration: Theme.animPopupIn; easing.type: Easing.OutCubic }
        }
    }
    SequentialAnimation {
        id: calCloseAnim
        ParallelAnimation {
            NumberAnimation { target: calPanel; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
            NumberAnimation { target: calPanel; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { cal.closing = false; } }
    }

    property int viewYear: new Date().getFullYear()
    property int viewMonth: new Date().getMonth()
    property bool gridVisible: true
    readonly property real calHighlightSize: Theme.calCellSize * 26 / 32

    function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate(); }
    function firstDow(y, m) { return new Date(y, m, 1).getDay(); }
    function prevMonth() { gridVisible = false; swapTimer.action = function() { if (cal.viewMonth === 0) { cal.viewMonth = 11; cal.viewYear--; } else cal.viewMonth--; }; swapTimer.start(); }
    function nextMonth() { gridVisible = false; swapTimer.action = function() { if (cal.viewMonth === 11) { cal.viewMonth = 0; cal.viewYear++; } else cal.viewMonth++; }; swapTimer.start(); }

    Timer {
        id: swapTimer; interval: Theme.animContentSwap; property var action
        onTriggered: { if (action) action(); cal.gridVisible = true; }
    }

    // Backdrop
    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: cal.close()
        MouseArea { anchors.fill: parent; onClicked: cal.close() }
    }

    // Panel
    Rectangle {
        id: calPanel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top; anchors.topMargin: Theme.popupTopMargin
        width: Theme.calWidth; height: calCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: 0.92
        transformOrigin: Item.Top
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: calCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Rectangle {
                    width: 24; height: 24; radius: Theme.hoverRadius; color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: navL.pressed ? 0.9 : (navL.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: navL.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text {
                        anchors.centerIn: parent; text: "󰅁"
                        color: navL.containsMouse ? Theme.fg : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    }
                    MouseArea { id: navL; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: cal.prevMonth() }
                }
                Text {
                    text: ["January","February","March","April","May","June","July","August","September","October","November","December"][cal.viewMonth] + " " + cal.viewYear
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true
                    Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter
                }
                Rectangle {
                    width: 24; height: 24; radius: Theme.hoverRadius; color: "transparent"
                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: navR.pressed ? 0.9 : (navR.containsMouse ? 0.6 : 0)
                        Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                    }
                    scale: navR.pressed ? 0.98 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center
                    Text {
                        anchors.centerIn: parent; text: "󰅂"
                        color: navR.containsMouse ? Theme.fg : Theme.fg4
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    }
                    MouseArea { id: navR; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: cal.nextMonth() }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

            RowLayout { spacing: 0; Layout.fillWidth: true
                Repeater { model: ["Su","Mo","Tu","We","Th","Fr","Sa"]
                    Text { required property string modelData; text: modelData; color: Theme.fg4
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                        Layout.preferredWidth: Theme.calCellSize; horizontalAlignment: Text.AlignHCenter }
                }
            }

            Grid {
                columns: 7; Layout.fillWidth: true; spacing: 0
                opacity: cal.gridVisible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.animContentSwap; easing.type: Easing.OutCubic } }

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

                        // Hover highlight for all valid days
                        Rectangle {
                            anchors.centerIn: parent; width: cal.calHighlightSize; height: cal.calHighlightSize; radius: width / 2
                            color: Theme.bg2
                            opacity: isCur && !isToday && dayCellMouse.containsMouse ? 0.5 : 0
                            Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
                        }

                        Rectangle {
                            id: todayCircle
                            anchors.centerIn: parent; width: cal.calHighlightSize; height: cal.calHighlightSize; radius: width / 2
                            color: isToday ? Theme.blueBright : "transparent"
                            // Gentle scale pulse on popup open for today
                            scale: isToday && cal.active ? 1.0 : 0.8
                            Behavior on scale { NumberAnimation { duration: Theme.animSpring; easing.type: Easing.OutBack } }
                        }
                        Text {
                            anchors.centerIn: parent; text: isCur ? dayNum : ""
                            color: isToday ? Theme.bg : (((index % 7) === 0 || (index % 7) === 6) ? Theme.fg4 : Theme.fg)
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: isToday
                        }
                        MouseArea {
                            id: dayCellMouse; anchors.fill: parent; hoverEnabled: isCur
                            cursorShape: isCur ? Qt.PointingHandCursor : Qt.ArrowCursor
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
