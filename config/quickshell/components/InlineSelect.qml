import QtQuick
import ".." as Root

FocusScope {
    id: root

    property var model: []
    property var currentValue: null
    property string currentText: ""
    property string placeholderText: "Select"
    property string secondaryText: ""
    property string fontFamily: Root.Theme.systemFamily
    property bool disabled: root.optionCount === 0
    property bool pending: false
    property bool expanded: false
    property int maxVisibleItems: 6
    property real rowHeight: Math.max(Root.Theme.btnHeight + 6, 32)
    property var textForValue: null
    property var matchesCurrent: null

    signal activated(var value)

    readonly property int optionCount: {
        if (!root.model)
            return 0;
        if (root.model.length !== undefined)
            return root.model.length;
        if (root.model.count !== undefined)
            return root.model.count;
        return 0;
    }
    readonly property real optionSpacing: 4
    readonly property int visibleItemCount: Math.min(root.maxVisibleItems, root.optionCount)
    readonly property real panelHeight: {
        if (root.visibleItemCount === 0)
            return 0;

        return root.visibleItemCount * root.rowHeight
            + Math.max(0, root.visibleItemCount - 1) * root.optionSpacing
            + 8;
    }

    implicitHeight: selectorCol.implicitHeight
    activeFocusOnTab: true
    readonly property bool interactive: root.optionCount > 0 && !root.disabled && !root.pending
    opacity: root.disabled ? 0.45 : (root.pending ? 0.72 : 1)
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape && root.expanded) {
            root.expanded = false;
            event.accepted = true;
        } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) && root.activeFocus && root.interactive) {
            root.expanded = !root.expanded;
            event.accepted = true;
        }
    }

    function optionText(value) {
        if (root.textForValue)
            return root.textForValue(value);
        return String(value);
    }

    function isCurrentOption(value) {
        if (root.matchesCurrent)
            return root.matchesCurrent(value, root.currentValue);
        return value === root.currentValue;
    }

    function currentIndex() {
        for (let i = 0; i < root.optionCount; i++) {
            if (root.isCurrentOption(root.model[i]))
                return i;
        }

        return -1;
    }

    function ensureCurrentVisible() {
        if (!root.expanded || root.optionCount === 0)
            return;

        let index = root.currentIndex();
        if (index < 0) {
            optionListFlick.contentY = 0;
            return;
        }

        let item = optionRepeater.itemAt(index);
        if (!item)
            return;

        let itemTop = item.y;
        let itemBottom = item.y + item.height;
        let viewTop = optionListFlick.contentY;
        let viewHeight = Math.max(optionListFlick.height, root.panelHeight - 8);
        let viewBottom = viewTop + viewHeight;

        if (itemTop < viewTop)
            optionListFlick.contentY = itemTop;
        else if (itemBottom > viewBottom)
            optionListFlick.contentY = itemBottom - viewHeight;
    }

    onExpandedChanged: {
        if (root.expanded)
            Qt.callLater(root.ensureCurrentVisible);
    }

    Column {
        id: selectorCol
        width: root.width
        spacing: root.expanded ? 6 : 0

        Rectangle {
            id: trigger
            width: parent.width
            height: root.rowHeight
            radius: Root.Theme.btnRadius + 2
            color: root.disabled ? Root.Theme.bg : (triggerArea.containsMouse || root.expanded ? Root.Theme.bg2 : Root.Theme.bg1)
            border.width: 1
            border.color: root.activeFocus ? Root.Theme.blueBright : (root.expanded ? Root.Theme.accent : (root.disabled ? Root.Theme.bg3 : (root.interactive && triggerArea.containsMouse ? Root.Theme.fg4 : Root.Theme.bg3)))
            Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
            Behavior on border.color { CAnim { duration: Root.Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
            scale: triggerArea.pressed ? 0.98 : 1.0
            Behavior on scale { Anim { duration: Root.Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
            transformOrigin: Item.Center

            Rectangle {
                anchors.fill: parent
                anchors.margins: -2
                radius: parent.radius + 2
                color: "transparent"
                border.width: root.activeFocus ? 2 : 0
                border.color: Root.Theme.blueBright
                opacity: root.activeFocus ? 1 : 0

                Behavior on opacity { Anim { duration: Root.Theme.animHover } }
            }

            StyledText {
                anchors {
                    left: parent.left
                    leftMargin: Root.Theme.listItemPadding
                    right: triggerMeta.left
                    rightMargin: 8
                    verticalCenter: parent.verticalCenter
                }
                animate: true
                text: root.currentText !== "" ? root.currentText : root.placeholderText
                color: root.disabled ? Root.Theme.fg4 : Root.Theme.fg
                font.family: root.fontFamily
                font.pixelSize: Root.Theme.fontSizeSmall
                elide: Text.ElideRight
            }

            Row {
                id: triggerMeta
                anchors {
                    right: parent.right
                    rightMargin: Root.Theme.listItemPadding
                    verticalCenter: parent.verticalCenter
                }
                spacing: 8

                Text {
                    visible: root.secondaryText !== ""
                    text: root.secondaryText
                    color: Root.Theme.fg4
                    font.family: root.fontFamily
                    font.pixelSize: Root.Theme.fontSizeSmall
                }

                Text {
                    text: ">"
                    color: root.expanded ? Root.Theme.accent : Root.Theme.fg4
                    font.family: root.fontFamily
                    font.pixelSize: Root.Theme.fontSizeSmall + 1
                    rotation: root.expanded ? 90 : 0
                    Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                    Behavior on rotation { Anim { duration: Root.Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                }
            }

            HoverLayer {
                id: triggerArea
                anchors.fill: parent
                disabled: !root.interactive
                hoverEnabled: true
                hoverOpacity: 0
                pressedOpacity: 0
                pressedScale: 1.0
                onClicked: {
                    root.forceActiveFocus();
                    root.expanded = !root.expanded;
                }
            }
        }

        Item {
            width: parent.width
            height: root.expanded ? panelBackground.implicitHeight : 0
            clip: true
            visible: height > 0 || root.expanded
            Behavior on height { Anim { duration: Root.Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }

            Rectangle {
                id: panelBackground
                width: parent.width
                implicitHeight: root.panelHeight
                height: implicitHeight
                y: root.expanded ? 0 : -8
                opacity: root.expanded ? 1 : 0
                radius: Root.Theme.btnRadius + 2
                color: Root.Theme.bg
                border.width: 1
                border.color: Root.Theme.bg3
                Behavior on opacity { Anim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                Behavior on y { Anim { duration: Root.Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }

                WheelFlickable {
                    id: optionListFlick
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    contentWidth: width
                    contentHeight: optionListContent.implicitHeight

                    Column {
                        id: optionListContent
                        width: optionListFlick.width
                        spacing: root.optionSpacing

                        Repeater {
                            id: optionRepeater
                            model: root.model

                            delegate: Rectangle {
                                required property var modelData
                                required property int index

                                width: optionListContent.width
                                height: root.rowHeight
                                radius: Root.Theme.hoverRadius

                                property bool isCurrent: root.isCurrentOption(modelData)

                                color: isCurrent ? Root.Theme.accent : (optionArea.containsMouse ? Root.Theme.bg2 : "transparent")
                                border.width: 1
                                border.color: isCurrent ? Root.Theme.accent : (optionArea.containsMouse ? Root.Theme.bg3 : "transparent")
                                Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                                Behavior on border.color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                                scale: optionArea.pressed ? 0.98 : 1.0
                                Behavior on scale { Anim { duration: Root.Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                                transformOrigin: Item.Center

                                Text {
                                    anchors {
                                        left: parent.left
                                        leftMargin: Root.Theme.listItemPadding
                                        right: parent.right
                                        rightMargin: Root.Theme.listItemPadding
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: root.optionText(modelData)
                                    color: isCurrent ? Root.Theme.bg : Root.Theme.fg
                                    font.family: root.fontFamily
                                    font.pixelSize: Root.Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }

                                HoverLayer {
                                    id: optionArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    hoverOpacity: 0
                                    pressedOpacity: 0
                                    pressedScale: 1.0
                                    onClicked: {
                                        root.forceActiveFocus();
                                        root.expanded = false;
                                        root.activated(modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
