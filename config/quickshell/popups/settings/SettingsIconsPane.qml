import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState
    required property bool writePending
    required property string pendingKey

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

        Components.SettingsPaneHeader {
            title: "Icons"
            iconSource: "../icons/certificate.svg"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Icon Theme"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
            }

            Text {
                text: "Choose the icon pack GTK, Qt, and the app switcher should use. Cards show representative icons from each theme."
                color: Theme.fg4
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            Components.IconThemeCards {
                Layout.fillWidth: true
                disabled: root.writePending
                pending: root.isPending("icon_theme")
                model: ShellOptions.iconThemeOptions
                currentValue: root.themeState.icon_theme || ""
                onActivated: (value) => root.setRequested("icon_theme", value)
            }
        }
    }
}
