import qs
import QtQuick
import "../components" as Components

Item {
    id: bellRoot
    implicitWidth: bellIcon.implicitWidth + 4; implicitHeight: bellIcon.implicitHeight
    property bool doNotDisturb: false; property int historyCount: 0; signal clicked()
    readonly property string tooltipText: {
        if (doNotDisturb) return "Do Not Disturb";
        if (historyCount > 0) return historyCount + " notification" + (historyCount !== 1 ? "s" : "");
        return "Notifications";
    }

    Components.StyledIcon {
        id: bellIcon; anchors.centerIn: parent
        animate: true
        source: bellRoot.doNotDisturb ? "../icons/bell-off.svg" : "../icons/bell.svg"
        color: { if (bellArea.containsMouse) return Theme.yellowBright; if (bellRoot.doNotDisturb) return Theme.fg4; return Theme.fg; }
        Behavior on color { Components.CAnim { duration: Theme.animHover } }
    }
    Rectangle {
        visible: bellRoot.historyCount > 0 && !bellRoot.doNotDisturb
        width: 5; height: 5; radius: 3; color: Theme.orangeBright
        anchors.top: bellIcon.top; anchors.right: bellIcon.right; anchors.topMargin: -1; anchors.rightMargin: -2
    }
    Components.BarTooltipArea {
        id: bellArea; tip: bellRoot.tooltipText
        onClicked: bellRoot.clicked()
    }
}
