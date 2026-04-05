import qs
import QtQuick
import "../components" as Components

Item {
    id: bellRoot
    implicitWidth: bellIcon.implicitWidth + 4; implicitHeight: bellIcon.implicitHeight
    property bool doNotDisturb: false; property int historyCount: 0; signal clicked()
    property string tooltipText: {
        if (doNotDisturb) return "Do Not Disturb";
        if (historyCount > 0) return historyCount + " notification" + (historyCount !== 1 ? "s" : "");
        return "Notifications";
    }

    Components.Icon {
        id: bellIcon; anchors.centerIn: parent
        source: bellRoot.doNotDisturb ? "../icons/bell-off.svg" : "../icons/bell.svg"
        color: { if (bellArea.containsMouse) return Theme.yellowBright; if (bellRoot.doNotDisturb) return Theme.fg4; return Theme.fg; }
    }
    Rectangle {
        visible: bellRoot.historyCount > 0 && !bellRoot.doNotDisturb
        width: 5; height: 5; radius: 3; color: Theme.orangeBright
        anchors.top: bellIcon.top; anchors.right: bellIcon.right; anchors.topMargin: -1; anchors.rightMargin: -2
    }
    MouseArea {
        id: bellArea; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
        onClicked: bellRoot.clicked()
        onContainsMouseChanged: {
            if (containsMouse) {
                let p = bellRoot.mapToGlobal(Qt.point(bellRoot.width / 2, bellRoot.height));
                TooltipService.show(bellRoot.tooltipText, p.x, p.y);
            } else {
                TooltipService.hide();
            }
        }
    }
}
