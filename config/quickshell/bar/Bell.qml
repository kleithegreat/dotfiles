import qs
import QtQuick

Item {
    id: bellRoot
    implicitWidth: bellText.implicitWidth + 4; implicitHeight: bellText.implicitHeight
    property bool doNotDisturb: false; property int historyCount: 0; signal clicked()

    Text {
        id: bellText; anchors.centerIn: parent
        text: bellRoot.doNotDisturb ? "󰂛" : "󰂚"
        color: { if (bellArea.containsMouse) return Theme.yellowBright; if (bellRoot.doNotDisturb) return Theme.fg4; return Theme.fg; }
        font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
    }
    Rectangle {
        visible: bellRoot.historyCount > 0 && !bellRoot.doNotDisturb
        width: 5; height: 5; radius: 3; color: Theme.orangeBright
        anchors.top: bellText.top; anchors.right: bellText.right; anchors.topMargin: -1; anchors.rightMargin: -2
    }
    MouseArea { id: bellArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: bellRoot.clicked() }
}
