import QtQuick
import Quickshell
import ".." as Root

// One panel of a cascading context menu, rendered from a QsMenuHandle.
// Placement and the parent/child relationship between panels belong to
// MenuChain; this file only draws rows and reports interaction.
Rectangle {
    id: panel

    property var menuHandle: null
    // Corner the entrance animation grows from, set by whoever places the panel.
    property int originCorner: Item.TopLeft

    // rowY/rowHeight are panel-local so the placer can map them itself.
    // immediate distinguishes a deliberate click from a hover dwell.
    signal submenuRequested(var entry, real rowY, real rowHeight, bool immediate)
    signal entryTriggered(var entry)
    signal plainEntryHovered()

    QsMenuOpener {
        id: menuOpener
        menu: panel.menuHandle
    }

    readonly property var entries: menuOpener.children ? menuOpener.children.values : []
    // Desktop menus align labels whenever any row carries a mark or an icon.
    readonly property bool hasGutter: {
        for (let i = 0; i < entries.length; i++) {
            if (entries[i].buttonType !== QsMenuButtonType.None || entries[i].icon)
                return true;
        }
        return false;
    }
    readonly property bool hasSubmenus: {
        for (let i = 0; i < entries.length; i++) {
            if (entries[i].hasChildren)
                return true;
        }
        return false;
    }
    readonly property int gutterWidth: hasGutter ? Root.Theme.menuGutter : 0
    readonly property int arrowWidth: hasSubmenus ? Root.Theme.iconSize + 4 : 0

    // A Column derives its implicit width from child widths, and the rows are
    // stretched to the panel, so the panel cannot size itself from the Column
    // without a binding loop. Measure the labels directly instead.
    property real labelWidth: 0
    function remeasure() {
        let widest = 0;
        for (let i = 0; i < entries.length; i++) {
            if (entries[i].isSeparator)
                continue;

            labelMetrics.text = entries[i].text ?? "";
            widest = Math.max(widest, labelMetrics.width);
        }

        labelWidth = widest;
    }
    onEntriesChanged: remeasure()
    Component.onCompleted: {
        remeasure();
        openAnim.restart();
    }

    TextMetrics {
        id: labelMetrics
        font.family: Root.Theme.fontFamily
        font.pixelSize: Root.Theme.fontSizeSmall
    }

    implicitWidth: Math.max(Root.Theme.menuMinWidth,
                            Math.min(Root.Theme.menuMaxWidth,
                                     Root.Theme.menuPadding * 2
                                     + Root.Theme.menuItemPadding * 2
                                     + gutterWidth + labelWidth + arrowWidth))
    implicitHeight: itemsCol.implicitHeight + Root.Theme.menuPadding * 2
    radius: Root.Theme.popupRadius
    color: Root.Theme.bg1
    border.width: 1
    border.color: Root.Theme.bg3

    transformOrigin: panel.originCorner
    opacity: 0
    scale: Root.Theme.popupStartScale
    // Reusing a panel for a sibling flyout should still read as a new menu.
    onMenuHandleChanged: openAnim.restart()

    ParallelAnimation {
        id: openAnim
        Anim {
            target: panel
            property: "opacity"
            from: 0
            to: 1
            duration: Root.Theme.animFast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Root.Theme.animCurveEnter
        }
        Anim {
            target: panel
            property: "scale"
            from: Root.Theme.popupStartScale
            to: 1.0
            duration: Root.Theme.animNormal
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Root.Theme.animCurveEmphasizedEnter
        }
    }

    // Swallow clicks that miss a row so they cannot dismiss the menu.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
    }

    Column {
        id: itemsCol
        x: Root.Theme.menuPadding
        y: Root.Theme.menuPadding
        width: panel.width - Root.Theme.menuPadding * 2

        Repeater {
            model: menuOpener.children

            delegate: Item {
                id: row
                required property var modelData

                readonly property bool isSeparator: modelData.isSeparator
                readonly property bool isEnabled: modelData.enabled && !isSeparator
                readonly property bool hasChildren: modelData.hasChildren
                readonly property bool isChecked: modelData.buttonType !== QsMenuButtonType.None
                    && modelData.checkState !== Qt.Unchecked

                width: itemsCol.width
                height: isSeparator ? Root.Theme.menuSeparatorHeight : Root.Theme.menuRowHeight

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: Root.Theme.menuItemPadding
                    width: parent.width - Root.Theme.menuItemPadding * 2
                    height: 1
                    color: Root.Theme.bg3
                    visible: row.isSeparator
                }

                HoverLayer {
                    visible: !row.isSeparator
                    // Greyed-out rows still track hover: moving onto one has to
                    // collapse an open flyout the same as any other row.
                    enabled: !row.isSeparator
                    cursorShape: row.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    color: Root.Theme.bg2
                    hoverOpacity: row.isEnabled ? 0.7 : 0.0
                    pressedOpacity: row.isEnabled ? 0.9 : 0.0
                    pressedScale: 1.0
                    radius: Root.Theme.hoverRadius
                    onContainsMouseChanged: {
                        if (!containsMouse)
                            return;

                        if (row.hasChildren)
                            panel.submenuRequested(row.modelData, row.y, row.height, false);
                        else
                            panel.plainEntryHovered();
                    }
                    onClicked: {
                        if (!row.isEnabled)
                            return;

                        if (row.hasChildren) {
                            panel.submenuRequested(row.modelData, row.y, row.height, true);
                            return;
                        }

                        row.modelData.triggered();
                        panel.entryTriggered(row.modelData);
                    }

                    Item {
                        x: Root.Theme.menuItemPadding
                        width: panel.gutterWidth
                        height: parent.height
                        visible: panel.hasGutter

                        Image {
                            id: entryIcon
                            anchors.verticalCenter: parent.verticalCenter
                            width: Root.Theme.iconSize
                            height: Root.Theme.iconSize
                            source: row.modelData.icon ?? ""
                            sourceSize.width: Root.Theme.iconSize * 2
                            sourceSize.height: Root.Theme.iconSize * 2
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                        }

                        Icon {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !entryIcon.visible && row.isChecked
                                && row.modelData.buttonType === QsMenuButtonType.CheckBox
                            source: row.modelData.checkState === Qt.PartiallyChecked
                                ? "../icons/circle-check.svg"
                                : "../icons/circle-check-filled.svg"
                            color: row.isEnabled ? Root.Theme.accent : Root.Theme.fgFaint
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: (Root.Theme.iconSize - width) / 2
                            width: 8
                            height: 8
                            radius: 4
                            visible: !entryIcon.visible && row.isChecked
                                && row.modelData.buttonType === QsMenuButtonType.RadioButton
                            color: row.isEnabled ? Root.Theme.accent : Root.Theme.fgFaint
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Root.Theme.menuItemPadding + panel.gutterWidth
                        width: parent.width - x - Root.Theme.menuItemPadding - panel.arrowWidth
                        text: row.modelData.text ?? ""
                        color: row.isEnabled ? Root.Theme.fg : Root.Theme.fgFaint
                        font.family: Root.Theme.fontFamily
                        font.pixelSize: Root.Theme.fontSizeSmall
                        elide: Text.ElideRight
                        visible: !row.isSeparator
                    }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width - Root.Theme.menuItemPadding - Root.Theme.iconSize
                        visible: row.hasChildren
                        source: "../icons/chevron-right.svg"
                        color: row.isEnabled ? Root.Theme.fg4 : Root.Theme.fgFaint
                    }
                }
            }
        }
    }
}
