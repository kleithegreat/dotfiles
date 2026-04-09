import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property var themeState
    required property bool writePending
    required property string pendingKey

    readonly property var cursorThemeOptions: [
        "Adwaita",
        "BreezeX-RosePine-Linux",
        "BreezeX-RosePineDawn-Linux",
        "Bibata-Modern-Classic",
        "Bibata-Modern-Ice",
        "Bibata-Original-Classic",
        "Bibata-Original-Ice"
    ]

    signal setRequested(string key, string value)

    function isPending(key) {
        return root.writePending && root.pendingKey === key;
    }

    anchors.fill: parent
    contentHeight: mouseCol.implicitHeight
    clip: true

    ColumnLayout {
        id: mouseCol
        width: parent.width
        spacing: 16

        RowLayout { Layout.fillWidth: true; spacing: 8
            Components.Icon { source: "../icons/cursor.svg"; color: Theme.fg }
            Text { text: "Mouse"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        RowLayout {
            Layout.fillWidth: true; spacing: 8

            Text {
                text: "Cursor Theme"
                color: Theme.fg3
                font.family: Theme.systemFamily
                font.pixelSize: Theme.fontSizeSmall
                Layout.preferredWidth: Math.max(Theme.fontSize * 8, 104)
            }

            Components.InlineSelect {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                disabled: root.writePending
                pending: root.isPending("cursor_theme")
                model: root.cursorThemeOptions
                currentValue: root.themeState.cursor_theme
                currentText: root.themeState.cursor_theme || ""
                secondaryText: root.cursorThemeOptions.length + " themes"
                fontFamily: Theme.systemFamily
                maxVisibleItems: 7
                onActivated: (value) => root.setRequested("cursor_theme", value)
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

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
                opacity: root.isPending("cursor_size") ? 0.72 : 1
                color: cursorSizeMinus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1; border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text { anchors.centerIn: parent; text: "\u2212"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }

                Components.HoverLayer {
                    id: cursorSizeMinus
                    disabled: root.writePending
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
                opacity: root.isPending("cursor_size") ? 0.72 : 1
                color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize
                width: 28; horizontalAlignment: Text.AlignHCenter
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }
            }

            Rectangle {
                width: 28; height: Theme.btnHeight; radius: Theme.btnRadius
                opacity: root.isPending("cursor_size") ? 0.72 : 1
                color: cursorSizePlus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1; border.color: Theme.bg3
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }

                Components.HoverLayer {
                    id: cursorSizePlus
                    disabled: root.writePending
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
