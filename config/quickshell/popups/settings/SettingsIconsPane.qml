import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState

    signal setRequested(string key, string value)

    anchors.fill: parent
    contentHeight: iconsCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: iconsCol
        width: parent.width
        spacing: 16

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/cursor.svg"; color: Theme.fg }
            Text { text: "Icons & Cursors"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        // Icon Theme
        RowLayout {
            Layout.fillWidth: true; spacing: 8

            Text {
                text: "Icon Theme"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Components.InlineDropdown {
                id: iconSelect
                Layout.preferredWidth: 180
                Layout.alignment: Qt.AlignTop
                model: ["Neuwaita", "Papirus-Dark", "Papirus", "Papirus-Light", "Adwaita", "hicolor"]
                currentValue: root.themeState.icon_theme
                onExpandedChanged: {
                    if (expanded)
                        cursorSelect.expanded = false;
                }
                onActivated: (value) => root.setRequested("icon_theme", value)
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        // Cursor Theme
        RowLayout {
            Layout.fillWidth: true; spacing: 8

            Text {
                text: "Cursor Theme"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Components.InlineDropdown {
                id: cursorSelect
                Layout.preferredWidth: 180
                Layout.alignment: Qt.AlignTop
                model: ["Adwaita", "BreezeX-RosePine-Linux", "BreezeX-RosePineDawn-Linux"]
                currentValue: root.themeState.cursor_theme
                onExpandedChanged: {
                    if (expanded)
                        iconSelect.expanded = false;
                }
                onActivated: (value) => root.setRequested("cursor_theme", value)
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        // Cursor Size
        RowLayout {
            Layout.fillWidth: true; spacing: 8

            Text {
                text: "Cursor Size"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true
            }

            Rectangle {
                width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                color: csMinus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1; border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Text { anchors.centerIn: parent; text: "\u2212"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }

                Components.HoverLayer {
                    id: csMinus
                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                    onClicked: {
                        let s = (root.themeState.cursor_size || 24) - 4;
                        if (s >= 16)
                            root.setRequested("cursor_size", String(s));
                    }
                }
            }

            Text {
                text: String(root.themeState.cursor_size || 24)
                color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize
                width: 28; horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                color: csPlus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1; border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }

                Components.HoverLayer {
                    id: csPlus
                    cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                    hoverOpacity: 0; pressedOpacity: 0; pressedScale: 1.0
                    onClicked: {
                        let s = (root.themeState.cursor_size || 24) + 4;
                        if (s <= 48)
                            root.setRequested("cursor_size", String(s));
                    }
                }
            }
        }
    }
}
