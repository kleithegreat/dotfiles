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
    property int focusedCategory: selectedCategory

    signal categorySelected(int index)

    function isCategoryHidden(index) {
        for (var i = 0; i < hiddenCategories.length; i++)
            if (hiddenCategories[i] === index) return true;
        return false;
    }

    function visibleCategoryIndexes() {
        let categories = [];

        for (let i = 0; i < root.categoryNames.length; i++) {
            if (!root.isCategoryHidden(i))
                categories.push(i);
        }

        return categories;
    }

    function syncFocusedCategory() {
        let visible = root.visibleCategoryIndexes();

        if (!visible.length)
            return;

        if (visible.indexOf(root.focusedCategory) >= 0)
            return;

        root.focusedCategory = visible.indexOf(root.selectedCategory) >= 0 ? root.selectedCategory : visible[0];
    }

    function moveFocusedCategory(delta) {
        let visible = root.visibleCategoryIndexes();
        let currentIndex = visible.indexOf(root.focusedCategory);

        if (!visible.length)
            return;

        if (currentIndex < 0)
            currentIndex = visible.indexOf(root.selectedCategory);
        if (currentIndex < 0)
            currentIndex = 0;

        currentIndex = Math.max(0, Math.min(visible.length - 1, currentIndex + delta));
        root.focusedCategory = visible[currentIndex];
    }

    function activateFocusedCategory() {
        root.syncFocusedCategory();
        root.categorySelected(root.focusedCategory);
    }

    function ensureItemVisible(item) {
        if (!item)
            return;

        let itemTop = item.y;
        let itemBottom = itemTop + item.height;
        let viewTop = sidebarFlickable.contentY;
        let viewBottom = viewTop + sidebarFlickable.height;

        if (itemTop < viewTop)
            sidebarFlickable.contentY = itemTop;
        else if (itemBottom > viewBottom)
            sidebarFlickable.contentY = itemBottom - sidebarFlickable.height;
    }

    readonly property int contentPadding: 8

    width: {
        let available = parent ? parent.width : 190;
        let preferred = Math.round((Theme.fontSizeLarge + root.contentPadding) * 11);
        let proportional = Math.round(available * 0.28);
        return Math.min(Math.max(proportional, preferred), Math.round(available * 0.4));
    }
    height: parent.height
    activeFocusOnTab: true
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Up) {
            root.moveFocusedCategory(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.moveFocusedCategory(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Home) {
            let visible = root.visibleCategoryIndexes();
            if (visible.length)
                root.focusedCategory = visible[0];
            event.accepted = true;
        } else if (event.key === Qt.Key_End) {
            let visible = root.visibleCategoryIndexes();
            if (visible.length)
                root.focusedCategory = visible[visible.length - 1];
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.activateFocusedCategory();
            event.accepted = true;
        }
    }
    onSelectedCategoryChanged: {
        root.focusedCategory = root.selectedCategory;
        root.syncFocusedCategory();
    }
    onActiveFocusChanged: {
        if (activeFocus) {
            root.focusedCategory = root.selectedCategory;
            root.syncFocusedCategory();
        }
    }
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
                        font.family: Theme.systemFamily
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
                        property bool isFocused: root.activeFocus && root.focusedCategory === categoryIndex

                        visible: !root.isCategoryHidden(categoryIndex)
                        Layout.fillWidth: true
                        Layout.preferredHeight: visible ? 32 : 0
                        radius: Theme.hoverRadius
                        color: isSelected ? Theme.bg2 : ((isFocused || sysCatArea.containsMouse) ? Theme.bg1 : "transparent")
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        onIsFocusedChanged: {
                            if (isFocused)
                                Qt.callLater(function() { root.ensureItemVisible(sysCatItem); });
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -1
                            radius: parent.radius + 1
                            color: "transparent"
                            border.width: sysCatItem.isFocused ? 1 : 0
                            border.color: Theme.blueBright
                            opacity: sysCatItem.isFocused ? 1 : 0
                            Behavior on opacity { Components.Anim { duration: Theme.animHover } }
                        }

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

                            Components.Icon {
                                source: root.categoryIcons[sysCatItem.categoryIndex]
                                color: sysCatItem.isSelected ? Theme.accent : Theme.fg4
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: root.categoryNames[sysCatItem.categoryIndex]
                                color: sysCatItem.isSelected ? Theme.fg : Theme.fg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                font.family: Theme.systemFamily
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
                            onClicked: {
                                root.focusedCategory = sysCatItem.categoryIndex;
                                root.categorySelected(sysCatItem.categoryIndex);
                            }
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
                        font.family: Theme.systemFamily
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
                        property bool isFocused: root.activeFocus && root.focusedCategory === categoryIndex

                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: Theme.hoverRadius
                        color: isSelected ? Theme.bg2 : ((isFocused || appCatArea.containsMouse) ? Theme.bg1 : "transparent")
                        Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        onIsFocusedChanged: {
                            if (isFocused)
                                Qt.callLater(function() { root.ensureItemVisible(appCatItem); });
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: -1
                            radius: parent.radius + 1
                            color: "transparent"
                            border.width: appCatItem.isFocused ? 1 : 0
                            border.color: Theme.blueBright
                            opacity: appCatItem.isFocused ? 1 : 0
                            Behavior on opacity { Components.Anim { duration: Theme.animHover } }
                        }

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

                            Components.Icon {
                                source: root.categoryIcons[appCatItem.categoryIndex]
                                color: appCatItem.isSelected ? Theme.accent : Theme.fg4
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                Layout.alignment: Qt.AlignVCenter
                            }

                            Text {
                                text: root.categoryNames[appCatItem.categoryIndex]
                                color: appCatItem.isSelected ? Theme.fg : Theme.fg3
                                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                                font.family: Theme.systemFamily
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
                            onClicked: {
                                root.focusedCategory = appCatItem.categoryIndex;
                                root.categorySelected(appCatItem.categoryIndex);
                            }
                        }
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
