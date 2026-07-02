pragma ComponentBehavior: Bound
import QtQuick
import ".." as Root

CardGrid {
    id: root

    property string currentValue: ""
    property bool disabled: false
    property bool pending: false

    signal activated(string schemeName)

    minCardWidth: Math.max(Root.Theme.fontSize * 11, 168)
    emptyText: "No color schemes found."

    cardDelegate: ColorSchemeCard {
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
