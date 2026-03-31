import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Rectangle {
    id: root
    required property int selectedCategory
    required property var categoryNames
    required property var categoryIcons
    required property int systemCategoryCount

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

        // ── System section ───────────────────────────────────

        Item {
            visible: root.systemCategoryCount > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 36

            Text {
                text: "System"
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
            visible: root.systemCategoryCount > 0
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.bg3
        }

        Item {
            visible: root.systemCategoryCount > 0
            Layout.preferredHeight: 4
        }

        Repeater {
            model: root.systemCategoryCount

            delegate: Rectangle {
                id: sysCatItem
                required property int index
                property int categoryIndex: index
                property bool isSelected: root.selectedCategory === categoryIndex

                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Theme.hoverRadius
                color: isSelected ? Theme.bg2 : (sysCatArea.containsMouse ? Theme.bg1 : "transparent")
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Rectangle {
                    visible: sysCatItem.isSelected
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
                        text: root.categoryIcons[sysCatItem.categoryIndex]
                        color: sysCatItem.isSelected ? Theme.accent : Theme.fg4
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: root.categoryNames[sysCatItem.categoryIndex]
                        color: sysCatItem.isSelected ? Theme.fg : Theme.fg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                    }
                }

                Components.HoverLayer {
                    id: sysCatArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.categorySelected(sysCatItem.categoryIndex)
                }
            }
        }

        // ── Spacer between sections ──────────────────────────

        Item {
            visible: root.systemCategoryCount > 0
            Layout.preferredHeight: 8
        }

        // ── Appearance section ───────────────────────────────

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
            model: root.categoryNames.length - root.systemCategoryCount

            delegate: Rectangle {
                id: appCatItem
                required property int index
                property int categoryIndex: index + root.systemCategoryCount
                property bool isSelected: root.selectedCategory === categoryIndex

                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: Theme.hoverRadius
                color: isSelected ? Theme.bg2 : (appCatArea.containsMouse ? Theme.bg1 : "transparent")
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Rectangle {
                    visible: appCatItem.isSelected
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
                        text: root.categoryIcons[appCatItem.categoryIndex]
                        color: appCatItem.isSelected ? Theme.accent : Theme.fg4
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Text {
                        text: root.categoryNames[appCatItem.categoryIndex]
                        color: appCatItem.isSelected ? Theme.fg : Theme.fg3
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                    }
                }

                Components.HoverLayer {
                    id: appCatArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: root.categorySelected(appCatItem.categoryIndex)
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}
