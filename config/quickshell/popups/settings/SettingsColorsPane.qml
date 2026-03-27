import qs
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var colorFamilies
    required property var themeState

    signal colorSchemeSelected(string schemeName)
    signal darkHintSelected(string value)

    function familyDisplayName(name) {
        if (name === "tokyonight")
            return "Tokyo Night";
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    anchors.fill: parent
    spacing: 16

    Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentHeight: colorGrid.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Grid {
            id: colorGrid
            width: parent.width
            columns: 3
            spacing: 8

            Repeater {
                model: root.colorFamilies.length

                delegate: Rectangle {
                    id: famCard
                    required property int index
                    property var variant: root.colorFamilies[index]
                    property bool isActive: root.themeState.color_scheme === (variant ? variant.schemeName : "")

                    width: (colorGrid.width - 16) / 3
                    height: 80
                    radius: Theme.btnRadius + 2
                    color: variant ? variant.bg : Theme.bg1
                    border.width: isActive ? 2 : 1
                    border.color: isActive ? (variant ? variant.accent : Theme.accent) : (famArea.containsMouse ? Theme.fg4 : Theme.bg3)
                    Behavior on border.color {
                        ColorAnimation {
                            duration: Theme.animSpring
                        }
                    }
                    scale: famArea.pressed ? 0.97 : 1.0
                    Behavior on scale {
                        NumberAnimation {
                            duration: Theme.animMicro
                            easing.type: Easing.OutCubic
                        }
                    }
                    transformOrigin: Item.Center

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: root.familyDisplayName(famCard.variant ? famCard.variant.family : "")
                                color: famCard.variant ? famCard.variant.fg : Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }

                            Text {
                                text: famCard.variant ? famCard.variant.variant : ""
                                color: famCard.variant ? famCard.variant.fg : Theme.fg4
                                opacity: 0.6
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                Layout.fillWidth: true
                            }

                            Text {
                                text: "✓"
                                visible: famCard.isActive
                                color: famCard.variant ? famCard.variant.accent : Theme.accent
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                                font.bold: true
                            }
                        }

                        Row {
                            spacing: 4
                            Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.accent : Theme.accent; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                            Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.red : Theme.red; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                            Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.green : Theme.green; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                            Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.blue : Theme.blue; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                            Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.yellow : Theme.yellow; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                            Rectangle { width: 14; height: 14; radius: 7; color: famCard.variant ? famCard.variant.purple : Theme.purple; border.width: 1; border.color: Qt.rgba(0, 0, 0, 0.15) }
                        }
                    }

                    MouseArea {
                        id: famArea
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: root.colorSchemeSelected(famCard.variant.schemeName)
                    }
                }
            }
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

        Text {
            text: "ELECTRON / BROWSER HINT"
            color: Theme.fg4
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            font.bold: true
        }

        Row {
            spacing: 6

            Rectangle {
                id: lightHintBtn
                property bool isActive: root.themeState.dark_hint === false

                width: lightHintLabel.implicitWidth + 20
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: isActive ? Theme.accent : (lightHintArea.containsMouse ? Theme.bg2 : Theme.bg1)
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animHover
                    }
                }
                border.width: 1
                border.color: isActive ? Theme.accent : Theme.bg3
                Behavior on border.color {
                    ColorAnimation {
                        duration: Theme.animSpring
                    }
                }
                scale: lightHintArea.pressed ? 0.95 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animMicro
                        easing.type: Easing.OutCubic
                    }
                }
                transformOrigin: Item.Center

                Text {
                    id: lightHintLabel
                    anchors.centerIn: parent
                    text: "Light"
                    color: lightHintBtn.isActive ? Theme.bg : Theme.fg
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.animHover
                        }
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                MouseArea {
                    id: lightHintArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.darkHintSelected("light")
                }
            }

            Rectangle {
                id: darkHintBtn
                property bool isActive: root.themeState.dark_hint !== false

                width: darkHintLabel.implicitWidth + 20
                height: Theme.btnHeight
                radius: Theme.btnRadius
                color: isActive ? Theme.accent : (darkHintArea.containsMouse ? Theme.bg2 : Theme.bg1)
                Behavior on color {
                    ColorAnimation {
                        duration: Theme.animHover
                    }
                }
                border.width: 1
                border.color: isActive ? Theme.accent : Theme.bg3
                Behavior on border.color {
                    ColorAnimation {
                        duration: Theme.animSpring
                    }
                }
                scale: darkHintArea.pressed ? 0.95 : 1.0
                Behavior on scale {
                    NumberAnimation {
                        duration: Theme.animMicro
                        easing.type: Easing.OutCubic
                    }
                }
                transformOrigin: Item.Center

                Text {
                    id: darkHintLabel
                    anchors.centerIn: parent
                    text: "Dark"
                    color: darkHintBtn.isActive ? Theme.bg : Theme.fg
                    Behavior on color {
                        ColorAnimation {
                            duration: Theme.animHover
                        }
                    }
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                }

                MouseArea {
                    id: darkHintArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    onClicked: root.darkHintSelected("dark")
                }
            }
        }
    }
}
