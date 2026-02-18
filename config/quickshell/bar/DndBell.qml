import qs
import QtQuick

Text {
    text: State.doNotDisturb ? "󰂜" : "󰂚"
    color: State.doNotDisturb ? Theme.fg4 : Theme.fg
    font.family: Theme.fontFamily
    font.pixelSize: Theme.iconSize

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: (mouse) => {
            if (mouse.button === Qt.LeftButton) {
                State.drawerVisible = !State.drawerVisible;
            } else {
                State.doNotDisturb = !State.doNotDisturb;
            }
        }
    }
}
