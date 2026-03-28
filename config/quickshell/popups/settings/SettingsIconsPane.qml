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

        Text { text: "ICON THEME"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: ["Neuwaita", "Papirus-Dark", "Papirus", "Papirus-Light", "Adwaita", "hicolor"]

                delegate: Rectangle {
                    id: itBtn
                    required property string modelData
                    required property int index
                    property bool isCurrent: root.themeState.icon_theme === modelData

                    width: itLabel.implicitWidth + 16
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: isCurrent ? Theme.accent : (itArea.containsMouse ? Theme.bg2 : Theme.bg1)
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    border.width: 1
                    border.color: isCurrent ? Theme.accent : Theme.bg3
                    Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                    scale: itArea.pressed ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center

                    Text {
                        id: itLabel
                        anchors.centerIn: parent
                        text: itBtn.modelData
                        color: itBtn.isCurrent ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    }

                    MouseArea {
                        id: itArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.setRequested("icon_theme", itBtn.modelData)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Text { text: "CURSOR THEME"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }

        Flow {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: ["Adwaita", "BreezeX-RosePine-Linux", "BreezeX-RosePineDawn-Linux"]

                delegate: Rectangle {
                    id: ctBtn
                    required property string modelData
                    required property int index
                    property bool isCurrent: root.themeState.cursor_theme === modelData

                    width: ctLabel.implicitWidth + 16
                    height: Theme.btnHeight
                    radius: Theme.btnRadius
                    color: isCurrent ? Theme.accent : (ctArea.containsMouse ? Theme.bg2 : Theme.bg1)
                    Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    border.width: 1
                    border.color: isCurrent ? Theme.accent : Theme.bg3
                    Behavior on border.color { ColorAnimation { duration: Theme.animSpring } }
                    scale: ctArea.pressed ? 0.95 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
                    transformOrigin: Item.Center

                    Text {
                        id: ctLabel
                        anchors.centerIn: parent
                        text: ctBtn.modelData
                        color: ctBtn.isCurrent ? Theme.bg : Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Behavior on color { ColorAnimation { duration: Theme.animHover } }
                    }

                    MouseArea {
                        id: ctArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.setRequested("cursor_theme", ctBtn.modelData)
                    }
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

        Row {
            spacing: 8

            Text { text: "Cursor Size:"; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }

            Rectangle {
                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: csMinus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { ColorAnimation { duration: Theme.animHover } }

                Text { anchors.centerIn: parent; text: "−"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }

                MouseArea {
                    id: csMinus
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: {
                        let s = (root.themeState.cursor_size || 24) - 4;
                        if (s >= 16)
                            root.setRequested("cursor_size", String(s));
                    }
                }
            }

            Text { text: String(root.themeState.cursor_size || 24); color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; width: 28; horizontalAlignment: Text.AlignHCenter; height: Theme.btnHeight; verticalAlignment: Text.AlignVCenter }

            Rectangle {
                width: 28
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: csPlus.containsMouse ? Theme.bg2 : Theme.bg1
                border.width: 1
                border.color: Theme.bg3
                Behavior on color { ColorAnimation { duration: Theme.animHover } }

                Text { anchors.centerIn: parent; text: "+"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize }

                MouseArea {
                    id: csPlus
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
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
