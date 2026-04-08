import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var colorFamilies
    required property var themeState
    required property bool writePending
    required property string pendingKey

    signal colorSchemeSelected(string schemeName)
    signal darkHintSelected(string value)

    function isPending(key) {
        return root.writePending && root.pendingKey === key;
    }

    anchors.fill: parent
    contentWidth: width
    contentHeight: colorsCol.implicitHeight
    clip: true

    ColumnLayout {
        id: colorsCol
        width: root.width
        spacing: 12

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/palette.svg"; color: Theme.fg }
            Text { text: "Colors"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "COLOR SCHEME"
                color: Theme.fg4
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                font.bold: true
            }

            Text {
                text: root.colorFamilies.length === 1
                    ? "1 scheme available"
                    : root.colorFamilies.length + " schemes available"
                color: Theme.fg4
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall - 1
            }

            Components.ColorSchemeCards {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                model: root.colorFamilies
                currentValue: root.themeState.color_scheme || ""
                disabled: root.writePending
                pending: root.isPending("color_scheme")
                onActivated: (schemeName) => root.colorSchemeSelected(schemeName)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Theme.bg3
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                opacity: root.isPending("dark_hint") ? 0.72 : 1
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text {
                    text: root.themeState.dark_hint === false ? "Prefer light browser theme" : "Prefer dark browser theme"
                    color: Theme.fg
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                }

                Text {
                    text: root.themeState.dark_hint === false ? "Light" : "Dark"
                    color: root.themeState.dark_hint === false ? Theme.fg4 : Theme.fg3
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                Components.ToggleSwitch {
                    checked: root.themeState.dark_hint !== false
                    disabled: root.writePending
                    pending: root.isPending("dark_hint")
                    onToggled: root.darkHintSelected(root.themeState.dark_hint === false ? "dark" : "light")
                }
            }
        }
    }
}
