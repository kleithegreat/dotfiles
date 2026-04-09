import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState
    required property bool writePending
    required property string pendingKey

    readonly property var iconThemeOptions: [
        "Neuwaita",
        "Colloid",
        "Colloid-Dark",
        "Colloid-Light",
        "Papirus-Dark",
        "Papirus",
        "Papirus-Light",
        "Adwaita",
        "hicolor"
    ]

    signal setRequested(string key, string value)

    function isPending(key) {
        return root.writePending && root.pendingKey === key;
    }

    anchors.fill: parent
    contentHeight: iconsCol.implicitHeight
    clip: true

    ColumnLayout {
        id: iconsCol
        width: parent.width
        spacing: 16

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/certificate.svg"; color: Theme.fg }
            Text { text: "Icons"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        RowLayout {
            Layout.fillWidth: true; spacing: 8

            Text {
                text: "Icon Theme"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: Math.max(Theme.fontSize * 8, 104)
            }

            Components.InlineSelect {
                id: iconSelect
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                disabled: root.writePending
                pending: root.isPending("icon_theme")
                model: root.iconThemeOptions
                currentValue: root.themeState.icon_theme
                currentText: root.themeState.icon_theme || ""
                secondaryText: root.iconThemeOptions.length + " themes"
                fontFamily: Theme.systemFamily
                maxVisibleItems: 7
                onActivated: (value) => root.setRequested("icon_theme", value)
            }
        }
    }
}
