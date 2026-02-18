import qs
import QtQuick

Text {
    id: clock
    property string timeStr: ""
    text: timeStr
    color: Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.fontSize
    font.bold: true

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            let d = new Date();
            let hours = d.getHours();
            let ampm = hours >= 12 ? "PM" : "AM";
            hours = hours % 12;
            if (hours === 0) hours = 12;
            let mins = d.getMinutes().toString().padStart(2, '0');
            let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
            let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
            clock.timeStr = days[d.getDay()] + " " + months[d.getMonth()] + " " + d.getDate() + "  " + hours + ":" + mins + " " + ampm;
        }
    }
}
