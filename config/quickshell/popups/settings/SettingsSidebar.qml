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
    property var hiddenCategories: []

    signal categorySelected(int index)

    function isCategoryHidden(index) {
        return hiddenCategories.indexOf(index) !== -1;
    }

    readonly property int contentPadding: 8

    component CategoryRow: Rectangle {
        id: catItem
        required property int index
        property int indexOffset: 0
        readonly property int categoryIndex: index + indexOffset
        readonly property bool isSelected: root.selectedCategory === categoryIndex

        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: Theme.hoverRadius
        color: isSelected ? Theme.bg2 : (catArea.containsMouse ? Theme.bg1 : "transparent")
        Behavior on color { Components.StdCAnim { duration: Theme.animHover } }

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

            Components.Icon {
                source: root.categoryIcons[catItem.categoryIndex]
                color: catItem.isSelected ? Theme.accent : Theme.fg4
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                text: root.categoryNames[catItem.categoryIndex]
                color: catItem.isSelected ? Theme.fg : Theme.fg3
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
            }
        }

        Components.HoverLayer {
            id: catArea
            flat: true
            onClicked: root.categorySelected(catItem.categoryIndex)
        }
    }

    width: {
        let available = parent ? parent.width : 190;
        let preferred = Math.round((Theme.fontSizeLarge + root.contentPadding) * 11);
        let proportional = Math.round(available * 0.28);
        return Math.min(Math.max(proportional, preferred), Math.round(available * 0.4));
    }
    height: parent.height
    color: Theme.bg0_h
    radius: Theme.popupRadius
    topRightRadius: 0
    bottomRightRadius: 0

    Components.WheelFlickable {
        id: sidebarFlickable
        anchors.fill: parent
        contentWidth: width
        contentHeight: sidebarContent.height
        clip: true

        Item {
            id: sidebarContent
            width: sidebarFlickable.width
            height: Math.max(sidebarColumn.implicitHeight + root.contentPadding * 2, sidebarFlickable.height)

            ColumnLayout {
                id: sidebarColumn
                anchors.fill: parent
                anchors.margins: root.contentPadding
                spacing: 2

                // System section
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

                Components.Divider {
                    visible: root.systemCategoryCount > 0
                }

                Item {
                    visible: root.systemCategoryCount > 0
                    Layout.preferredHeight: 4
                }

                Repeater {
                    model: root.systemCategoryCount

                    delegate: CategoryRow {
                        visible: !root.isCategoryHidden(categoryIndex)
                    }
                }

                // Spacer between sections
                Item {
                    visible: root.systemCategoryCount > 0
                    Layout.preferredHeight: 8
                }

                // Appearance section
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

                Components.Divider {}

                Item {
                    Layout.preferredHeight: 4
                }

                Repeater {
                    model: root.categoryNames.length - root.systemCategoryCount

                    delegate: CategoryRow {
                        indexOffset: root.systemCategoryCount
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }
            }
        }
    }
}
