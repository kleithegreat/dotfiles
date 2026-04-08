import QtQuick
import ".." as Root

FocusScope {
    id: root

    property var model: []
    property var currentValue: null
    property string placeholderText: "Select"
    property var textForValue: null
    property bool disabled: false
    property bool pending: false
    property bool expanded: false
    property int maxVisibleItems: 6

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
    readonly property int visibleItemCount: Math.min(root.maxVisibleItems, root.optionCount)
    readonly property real panelHeight: {
        if (root.visibleItemCount === 0)
            return 0;
        return root.visibleItemCount * Root.Theme.btnHeight
            + Math.max(0, root.visibleItemCount - 1) * 2 + 8;
    }

    implicitHeight: dropdownCol.implicitHeight

    function optionText(value) {
        if (root.textForValue)
            return root.textForValue(value);
        return String(value);
    }

    function currentDisplayText() {
        if (root.currentValue !== null && root.currentValue !== undefined)
            return root.optionText(root.currentValue);
        return root.placeholderText;
    }

    function isCurrentOption(value) {
        return value === root.currentValue;
    }

    readonly property bool interactive: !root.disabled && !root.pending && root.optionCount > 0
    opacity: root.disabled ? 0.45 : (root.pending ? 0.72 : 1)
    Behavior on opacity { Anim { duration: Root.Theme.animHover } }

    Column {
        id: dropdownCol
        width: root.width
        spacing: root.expanded ? 4 : 0

        // ── Trigger ──────────────────────────────────────
        Rectangle {
            id: triggerBtn
            width: parent.width
            height: Root.Theme.btnHeight
            radius: Root.Theme.btnRadius
            color: root.disabled ? Root.Theme.bg : (triggerArea.containsMouse || root.expanded ? Root.Theme.bg2 : Root.Theme.bg1)
            border.width: 1
            border.color: root.expanded ? Root.Theme.accent : (root.interactive && triggerArea.containsMouse ? Root.Theme.fg4 : Root.Theme.bg3)
            Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
            Behavior on border.color { CAnim { duration: Root.Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
            scale: triggerArea.pressed ? 0.98 : 1.0
            Behavior on scale { Anim { duration: Root.Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
            transformOrigin: Item.Center

            Text {
                anchors {
                    left: parent.left; leftMargin: Root.Theme.listItemPadding
                    right: chevron.left; rightMargin: 4
                    verticalCenter: parent.verticalCenter
                }
                text: root.currentDisplayText()
                color: Root.Theme.fg
                font.family: Root.Theme.systemFamily
                font.pixelSize: Root.Theme.fontSizeSmall
                elide: Text.ElideRight
            }

            Text {
                id: chevron
                anchors {
                    right: parent.right; rightMargin: Root.Theme.listItemPadding
                    verticalCenter: parent.verticalCenter
                }
                text: "▾"
                color: root.expanded ? Root.Theme.accent : Root.Theme.fg4
                font.family: Root.Theme.systemFamily
                font.pixelSize: Root.Theme.fontSizeSmall
                rotation: root.expanded ? 180 : 0
                Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                Behavior on rotation { Anim { duration: Root.Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
            }

            HoverLayer {
                id: triggerArea
                disabled: !root.interactive
                hoverOpacity: 0
                pressedOpacity: 0
                pressedScale: 1.0
                onClicked: root.expanded = !root.expanded
            }
        }

        // ── Options panel ────────────────────────────────
        Item {
            width: parent.width
            height: root.expanded ? panelBg.implicitHeight : 0
            clip: true
            visible: height > 0 || root.expanded
            Behavior on height { Anim { duration: Root.Theme.animSpring; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }

            Rectangle {
                id: panelBg
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
                    id: optionFlick
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true
                    contentWidth: width
                    contentHeight: optionCol.implicitHeight

                    Column {
                        id: optionCol
                        width: optionFlick.width
                        spacing: 2

                        Repeater {
                            model: root.model

                            delegate: Rectangle {
                                required property var modelData
                                required property int index
                                property bool isCurrent: root.isCurrentOption(modelData)

                                width: optionCol.width
                                height: Root.Theme.btnHeight
                                radius: Root.Theme.hoverRadius
                                color: isCurrent ? Root.Theme.accent : (optArea.containsMouse ? Root.Theme.bg2 : "transparent")
                                border.width: 1
                                border.color: isCurrent ? Root.Theme.accent : (optArea.containsMouse ? Root.Theme.bg3 : "transparent")
                                Behavior on color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                                Behavior on border.color { CAnim { duration: Root.Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                                scale: optArea.pressed ? 0.98 : 1.0
                                Behavior on scale { Anim { duration: Root.Theme.animMicro; easing.type: Easing.BezierSpline; easing.bezierCurve: Root.Theme.animCurveStandard } }
                                transformOrigin: Item.Center

                                Text {
                                    anchors {
                                        left: parent.left; leftMargin: Root.Theme.listItemPadding
                                        right: parent.right; rightMargin: Root.Theme.listItemPadding
                                        verticalCenter: parent.verticalCenter
                                    }
                                    text: root.optionText(modelData)
                                    color: isCurrent ? Root.Theme.bg : Root.Theme.fg
                                    font.family: Root.Theme.systemFamily
                                    font.pixelSize: Root.Theme.fontSizeSmall
                                    elide: Text.ElideRight
                                }

                                HoverLayer {
                                    id: optArea
                                    hoverOpacity: 0
                                    pressedOpacity: 0
                                    pressedScale: 1.0
                                    onClicked: {
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
