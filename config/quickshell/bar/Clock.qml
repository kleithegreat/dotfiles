import qs
import QtQuick

Item {
    id: clockRoot
    implicitWidth: clockText.implicitWidth
    implicitHeight: clockText.implicitHeight
    signal clicked()

    Text {
        id: clockText
        property string timeStr: ""
        text: timeStr
        color: clockArea.containsMouse ? Theme.yellowBright : Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true

        Timer {
            interval: 1000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: {
                let d = new Date();
                let h = d.getHours(), ap = h >= 12 ? "PM" : "AM";
                h = h % 12; if (h === 0) h = 12;
                let mi = d.getMinutes().toString().padStart(2, '0');
                let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
                let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
                clockText.timeStr = days[d.getDay()] + " " + months[d.getMonth()] + " " + d.getDate() + "  " + h + ":" + mi + " " + ap;
            }
        }
    }
    MouseArea {
        id: clockArea; anchors.fill: parent
        cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: clockRoot.clicked()
    }
}
