pragma ComponentBehavior: Bound
import QtQuick
import ".." as Root

CardGrid {
    id: root

    property string currentValue: ""
    property bool disabled: false
    property bool pending: false

    signal activated(string themeName)

    minCardWidth: Math.max(Root.Theme.fontSize * 10.5, 160)
    emptyText: "No icon themes found."

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

    cardDelegate: IconThemeCard {
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
