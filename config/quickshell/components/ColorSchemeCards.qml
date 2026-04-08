import QtQuick
import ".." as Root

Item {
    id: root

    property var model: []
    property string currentValue: ""
    property bool disabled: false
    property bool pending: false
    property real minCardWidth: Math.max(Root.Theme.fontSize * 11, 168)
    property real cardSpacing: 8

    signal activated(string schemeName)

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

            delegate: ColorSchemeCard {
                required property var modelData

                width: root.cardWidth
                scheme: modelData || ({})
                active: !!scheme && scheme.schemeName === root.currentValue
                disabled: root.disabled
                pending: root.pending
                onClicked: {
                    if (scheme && scheme.schemeName)
                        root.activated(scheme.schemeName);
                }
            }
        }
    }

    StyledText {
        id: emptyState
        visible: root.optionCount === 0
        width: root.width
        text: "No color schemes found."
        color: Root.Theme.fg4
        font.family: Root.Theme.systemFamily
        font.pixelSize: Root.Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }
}
