import QtQuick
import ".." as Root

MouseArea {
    id: root

    // Fill-parent tooltip hit area for bar modules: shows `tip` centered
    // below `target` on hover and re-shows it so the text stays live while
    // hovered.
    property Item target: parent
    property string tip: ""

    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    hoverEnabled: true

    function _show() {
        let p = root.target.mapToGlobal(Qt.point(root.target.width / 2, root.target.height));
        Root.TooltipService.show(root.tip, p.x, p.y);
    }

    onContainsMouseChanged: {
        if (containsMouse)
            _show();
        else
            Root.TooltipService.hide();
    }

    onTipChanged: {
        if (containsMouse)
            _show();
    }
}
