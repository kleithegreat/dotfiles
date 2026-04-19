pragma ComponentBehavior: Bound
import QtQuick
import ".." as Root

Item {
    id: root

    property var model: []
    property string currentValue: ""
    property bool disabled: false
    property bool pending: false
    property real minCardWidth: Math.max(Root.Theme.fontSize * 10.5, 160)
    property real cardSpacing: 8

    signal activated(string themeName)

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

    function themeNameForOption(option) {
        if (option && typeof option === "object") {
            if (option.name !== undefined)
                return String(option.name);
            if (option.value !== undefined)
                return String(option.value);
            if (option.themeName !== undefined)
                return String(option.themeName);
        }

        return String(option || "");
    }

    Grid {
        id: cardGrid
        visible: root.optionCount > 0
        width: root.width
        columns: root.columnCount
        spacing: root.cardSpacing

        Repeater {
            model: root.model

            delegate: IconThemeCard {
                required property var modelData

                property string optionThemeName: root.themeNameForOption(modelData)

                width: root.cardWidth
                themeName: optionThemeName
                active: optionThemeName === root.currentValue
                disabled: root.disabled
                pending: root.pending
                onClicked: {
                    if (optionThemeName !== "")
                        root.activated(optionThemeName);
                }
            }
        }
    }

    StyledText {
        id: emptyState
        visible: root.optionCount === 0
        width: root.width
        text: "No icon themes found."
        color: Root.Theme.fg4
        font.family: Root.Theme.systemFamily
        font.pixelSize: Root.Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }
}
