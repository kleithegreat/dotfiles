import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Rectangle {
    id: root
    required property int selectedCategory
    required property var categoryNames
    required property var categoryIcons

    signal categorySelected(int index)

    width: 190
    height: parent.height
    color: Theme.bg0_h
    radius: Theme.popupRadius
    topRightRadius: 0
    bottomRightRadius: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 2

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 36

            Text {
                text: "Appearance"
                anchors {
                    left: parent.left
                    leftMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                color: Theme.fg
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeLarge
                font.bold: true
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.bg3
        }

        Item {
            Layout.preferredHeight: 4
        }

        Repeater {
            model: root.categoryNames.length

            delegate: Rectangle {
                id: catItem
                required property int index
                property bool isSelected: root.selectedCategory === index

                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Theme.hoverRadius
                color: isSelected ? Theme.bg2 : (catArea.containsMouse ? Theme.bg1 : "transparent")
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Rectangle {
                    visible: catItem.isSelected
                    width: 3
                    height: 16
                    radius: 1.5
                    anchors {
                        left: parent.left
                        leftMargin: 2
                        verticalCenter: parent.verticalCenter
                    }
                    color: Theme.accent
                }

                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 12
                        rightMargin: 8
                    }
                    spacing: 10

                    Text {
                        text: root.categoryIcons[catItem.index]
                        color: catItem.isSelected ? Theme.accent : Theme.fg4
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: root.categoryNames[catItem.index]
                        color: catItem.isSelected ? Theme.fg : Theme.fg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                    }
                }

                Components.HoverLayer {
                    id: catArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.categorySelected(catItem.index)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
