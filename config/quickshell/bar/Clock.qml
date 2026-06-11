import qs
import QtQuick
import "../components" as Components

Item {
    id: clockRoot
    implicitWidth: charRow.width
    implicitHeight: refChar.implicitHeight
    signal clicked()

    property string timeStr: ""
    property string prevTimeStr: ""
    property color textColor: clockArea.containsMouse ? Theme.yellowBright : Theme.fg
    property string tooltipText: {
        // Reference timeStr only to register a binding dependency, so the
        // date below re-evaluates with each tick (e.g. across midnight).
        let _t = timeStr;
        let d = new Date();
        let days = ["Sunday","Monday","Tuesday","Wednesday","Thursday","Friday","Saturday"];
        let months = ["January","February","March","April","May","June","July","August","September","October","November","December"];
        return days[d.getDay()] + ", " + months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear();
    }

    // Measure a single monospace cell for slot dimensions
    Text {
        id: refChar
        visible: false
        text: "0"
        font.family: Theme.monoFamily; font.pixelSize: Theme.fontSize; font.bold: true
        renderType: Text.NativeRendering
    }

    Timer {
        interval: 1000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            let d = new Date();
            let h = d.getHours(), ap = h >= 12 ? "PM" : "AM";
            h = h % 12; if (h === 0) h = 12;
            let mi = d.getMinutes().toString().padStart(2, '0');
            let days = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
            let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
            clockRoot.prevTimeStr = clockRoot.timeStr;
            clockRoot.timeStr = days[d.getDay()] + " " + months[d.getMonth()] + " " + d.getDate().toString().padStart(2, ' ') + "  " + h.toString().padStart(2, ' ') + ":" + mi + " " + ap;
        }
    }

    Row {
        id: charRow

        Repeater {
            model: clockRoot.timeStr.length

            delegate: Item {
                id: slot
                required property int index
                width: refChar.implicitWidth
                height: refChar.implicitHeight
                clip: true

                property string currentChar: clockRoot.timeStr.charAt(index)
                property string previousChar: clockRoot.prevTimeStr.charAt(index)

                onCurrentCharChanged: {
                    if (previousChar.length > 0 && previousChar !== currentChar) {
                        outText.text = previousChar;
                        outText.y = 0;
                        inText.text = currentChar;
                        inText.y = slot.height;
                        rollAnim.restart();
                    } else {
                        inText.text = currentChar;
                        inText.y = 0;
                    }
                }

                Text {
                    id: outText
                    width: slot.width
                    font: refChar.font
                    renderType: Text.NativeRendering
                    color: clockRoot.textColor
                    y: -slot.height
                }

                Text {
                    id: inText
                    width: slot.width
                    font: refChar.font
                    renderType: Text.NativeRendering
                    color: clockRoot.textColor
                }

                ParallelAnimation {
                    id: rollAnim

                    Components.Anim {
                        target: outText
                        property: "y"
                        from: 0
                        to: -slot.height
                        duration: Theme.animContentSwap
                    }

                    Components.Anim {
                        target: inText
                        property: "y"
                        from: slot.height
                        to: 0
                        duration: Theme.animContentSwap
                    }
                }
            }
        }
    }

    MouseArea {
        id: clockArea
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        onClicked: clockRoot.clicked()
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = clockRoot.mapToGlobal(Qt.point(clockRoot.width / 2, clockRoot.height));
                TooltipService.show(clockRoot.tooltipText, p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
    }
}
