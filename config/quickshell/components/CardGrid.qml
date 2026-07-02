pragma ComponentBehavior: Bound
import QtQuick
import ".." as Root

// Responsive card grid: lays `cardDelegate` instances out in as many columns
// as fit `minCardWidth`, and shows `emptyText` when the model is empty.
Item {
    id: root

    property var model: []
    property real minCardWidth: 160
    property real cardSpacing: 8
    property string emptyText: ""
    property Component cardDelegate: null

    readonly property int optionCount: {
        if (!root.model)
            return 0;
        if (root.model.length !== undefined)
            return root.model.length;
        if (root.model.count !== undefined)
            return root.model.count;
        return 0;
    }

    readonly property int columnCount: {
        if (root.width <= 0)
            return 1;

        return Math.max(1, Math.floor((root.width + root.cardSpacing) / (root.minCardWidth + root.cardSpacing)));
    }

    readonly property real cardWidth: {
        if (root.width <= 0)
            return root.minCardWidth;

        return (root.width - Math.max(0, root.columnCount - 1) * root.cardSpacing) / Math.max(1, root.columnCount);
    }

    implicitHeight: root.optionCount > 0 ? cardGrid.implicitHeight : emptyState.implicitHeight

    Grid {
        id: cardGrid
        visible: root.optionCount > 0
        width: root.width
        columns: root.columnCount
        spacing: root.cardSpacing

        Repeater {
            model: root.model
            delegate: root.cardDelegate
        }
    }

    StyledText {
        id: emptyState
        visible: root.optionCount === 0
        width: root.width
        text: root.emptyText
        color: Root.Theme.fg4
        font.family: Root.Theme.fontFamily
        font.pixelSize: Root.Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }
}
