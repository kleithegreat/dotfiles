import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import "components" as Components

FocusScope {
    id: drawer
    property bool active: false; signal close()
    property bool closing: false
    property bool contentLoaded: false
    component StateLayer: Item {
        id: stateLayerRoot

        property color color: Theme.bg2
        property real radius: Theme.hoverRadius
        property real idleOpacity: 0.0
        property real hoverOpacity: 0.6
        property real pressedOpacity: 0.9
        readonly property alias containsMouse: hoverLayer.containsMouse
        readonly property alias pressed: hoverLayer.pressed
        signal clicked()

        Components.HoverLayer {
            id: hoverLayer
            anchors.fill: parent
            color: stateLayerRoot.color
            radius: stateLayerRoot.radius
            idleOpacity: stateLayerRoot.idleOpacity
            hoverOpacity: stateLayerRoot.hoverOpacity
            pressedOpacity: stateLayerRoot.pressedOpacity
            pressedScale: 1.0
            onClicked: stateLayerRoot.clicked()
        }
    }

    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: drawerContentLoader.item
    readonly property Item focusTarget: drawer
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    property real panelHeightHint: 240
    property int historyAnimationThreshold: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    /*
    Legacy per-popup PanelWindow wrapper retained during the overlay-host migration:
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:drawer"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle { anchors.fill: parent; color: "transparent"; focus: true; Keys.onEscapePressed: drawer.close()
        MouseArea { anchors.fill: parent; onClicked: drawer.close() }
    }
    */

    function currentHistoryMaxEntryId() {
        if (NotificationService.historyCount === 0)
            return 0;

        let newest = NotificationService.historyModel.get(0);
        return newest && newest.entryId !== undefined ? newest.entryId : 0;
    }

    Component.onCompleted: {
        historyAnimationThreshold = currentHistoryMaxEntryId();
    }

    function preparePanelForOpen() {
        let item = drawerContentLoader.item;
        if (!item)
            return false;

        item.opacity = 0;
        item.scale = 0.92;
        return true;
    }

    onActiveChanged: {
        if (active) {
            forceActiveFocus();
            contentLoaded = true;
            if (preparePanelForOpen())
                drawerOpenAnim.start();
        } else if (!closing) {
            if (drawerContentLoader.item) {
                closing = true;
                drawerCloseAnim.start();
            } else {
                closing = false;
            }
        }
    }

    SequentialAnimation {
        id: drawerOpenAnim
        ParallelAnimation {
            Components.Anim { target: drawerContentLoader.item; property: "opacity"; to: 1; duration: Theme.animPopupIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveEmphasizedEnter }
            SequentialAnimation {
                PauseAnimation { duration: 40 }
                Components.Anim { target: drawerContentLoader.item; property: "scale"; to: 1.0; duration: Theme.animPopupIn - 40; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveEmphasizedEnter }
            }
        }
    }
    SequentialAnimation {
        id: drawerCloseAnim
        ParallelAnimation {
            Components.Anim { target: drawerContentLoader.item; property: "opacity"; to: 0; duration: Theme.animPopupOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveExit }
            Components.Anim { target: drawerContentLoader.item; property: "scale"; to: 0.92; duration: Theme.animPopupOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveExit }
        }
        ScriptAction { script: { drawer.closing = false; } }
    }

    Keys.onEscapePressed: drawer.close()

    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.popupTopMargin
        anchors.rightMargin: Theme.gapOut
        width: drawerContentLoader.width
        height: drawerContentLoader.height
        visible: drawer.overlayVisible && !drawer.closing && height > 0 && (!drawerContentLoader.item || drawerContentLoader.item.opacity < 1)
        opacity: drawerContentLoader.item ? Math.max(0, 1 - drawerContentLoader.item.opacity) : 1
        radius: Theme.notifRadius
        color: Theme.bg1
        border.width: 1
        border.color: Theme.bg3
        Behavior on opacity { Components.Anim { duration: Theme.animHover } }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Loader {
        id: drawerContentLoader
        anchors.top: parent.top; anchors.right: parent.right
        anchors.topMargin: Theme.popupTopMargin; anchors.rightMargin: Theme.gapOut
        width: Theme.drawerWidth
        height: drawer.overlayVisible
            ? Math.min(item ? item.implicitHeight : drawer.panelHeightHint, parent.height - Theme.popupTopMargin - Theme.gapOut)
            : 0
        active: drawer.contentLoaded || drawer.active || drawer.closing
        asynchronous: true
        sourceComponent: drawerPanelComponent
        Behavior on height {
            Components.Anim {
                duration: Theme.animHeightResize
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }

        onLoaded: {
            drawer.panelHeightHint = Math.min(item.implicitHeight, drawer.height - Theme.popupTopMargin - Theme.gapOut);
            item.opacity = 0;
            item.scale = 0.92;
            if (drawer.active)
                drawerOpenAnim.start();
        }
    }

    Connections {
        target: drawerContentLoader.item

        function onImplicitHeightChanged() {
            drawer.panelHeightHint = Math.min(drawerContentLoader.item.implicitHeight, drawer.height - Theme.popupTopMargin - Theme.gapOut);
        }
    }

    Component {
        id: drawerPanelComponent

        Rectangle {
            id: drawerPanel
            anchors.fill: parent
            implicitHeight: Math.max(drawerCol.implicitHeight + Theme.notifPadding * 2, 200)
            radius: Theme.notifRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
            opacity: 0; scale: 0.92
            transformOrigin: Item.TopRight
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                id: drawerCol; anchors.fill: parent; anchors.margins: Theme.notifPadding; spacing: 8
            RowLayout { Layout.fillWidth: true; spacing: 8
                RowLayout { Layout.fillWidth: true; spacing: 6
                    Components.Icon { source: "../icons/bell.svg"; color: Theme.fg }
                    Text { text: "Notifications"; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.headerFontSize; font.bold: true; Layout.fillWidth: true }
                }

                // Clear button
                Rectangle {
                    visible: NotificationService.historyCount > 0
                    width: clrLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    StateLayer {
                        id: clrLayer
                        anchors.fill: parent
                        radius: parent.radius
                        color: Theme.bg2
                        onClicked: NotificationService.clearHistory()
                    }
                    scale: clrLayer.pressed ? 0.95 : 1.0
                    Behavior on scale { Components.Anim { duration: Theme.animMicro } }
                    transformOrigin: Item.Center
                    Text { id: clrLabel; anchors.centerIn: parent; text: "Clear"
                        color: clrLayer.containsMouse ? Theme.redBright : Theme.fg4
                        Behavior on color { Components.CAnim { duration: Theme.animHover } }
                        font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }
            Components.WheelFlickable {
                visible: NotificationService.historyCount > 0; Layout.fillWidth: true; Layout.fillHeight: true; Layout.minimumHeight: 40; Layout.maximumHeight: 400
                contentHeight: histCol.implicitHeight; clip: true
                Column { id: histCol; width: parent.width; spacing: Theme.notifSpacing
                    Repeater { id: historyList
                        model: NotificationService.historyModel
                        Rectangle {
                            id: hc; required property string appName; required property string summary; required property string body; required property int nid; required property int entryId; required property int index; required property string timeStr
                            width: histCol.width; height: hcC.implicitHeight + Theme.notifPadding; radius: Theme.btnRadius; color: Theme.bg2

                            property bool shouldAnimateEntry: hc.entryId > drawer.historyAnimationThreshold

                            opacity: shouldAnimateEntry ? 0 : 1
                            y: shouldAnimateEntry ? 8 : 0
                            scale: shouldAnimateEntry ? 0.92 : 1.0
                            Component.onCompleted: {
                                if (!shouldAnimateEntry)
                                    return;

                                drawer.historyAnimationThreshold = Math.max(drawer.historyAnimationThreshold, hc.entryId);
                                hcEnterAnim.delay = index * Theme.animStagger;
                                hcEnterAnim.start();
                            }
                            SequentialAnimation {
                                id: hcEnterAnim; property int delay: 0
                                PauseAnimation { duration: hcEnterAnim.delay }
                                ParallelAnimation {
                                    Components.Anim { target: hc; property: "opacity"; to: 1; duration: Theme.animContentSwap; easing.type: Easing.OutCubic }
                                    Components.Anim { target: hc; property: "y"; to: 0; duration: Theme.animContentSwap; easing.type: Easing.OutCubic }
                                    Components.Anim { target: hc; property: "scale"; to: 1.0; duration: Theme.animContentSwap; easing.type: Easing.OutBack; easing.overshoot: 1.07 }
                                }
                            }

                            ColumnLayout { id: hcC; spacing: 2
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.notifPadding / 2 }
                                RowLayout { Layout.fillWidth: true
                                    Text { text: hc.appName; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall - 1; elide: Text.ElideRight; Layout.fillWidth: true }
                                    Text { text: hc.timeStr; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall - 2; visible: text !== "" }
                                    Rectangle {
                                        width: 18; height: 18; radius: Theme.hoverRadius; color: "transparent"
                                        StateLayer {
                                            id: hxLayer
                                            anchors.fill: parent
                                            radius: parent.radius
                                            color: Theme.bg1
                                            onClicked: NotificationService.removeHistory(hc.nid)
                                        }
                                        scale: hxLayer.pressed ? 0.9 : 1.0
                                        Behavior on scale { Components.Anim { duration: Theme.animMicro } }
                                        transformOrigin: Item.Center
                                        Components.Icon { anchors.centerIn: parent; source: "../icons/close.svg"
                                            color: hxLayer.containsMouse ? Theme.redBright : Theme.fg4
                                            Behavior on color { Components.CAnim { duration: Theme.animHover } }
                                            iconSize: Theme.fontSizeSmall }
                                    }
                                }
                                Text { text: hc.summary; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text !== "" }
                                Text { text: hc.body; color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall - 1; wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                            }
                        }
                    }
                }
            }
            // Empty state with icon
            Item {
                visible: NotificationService.historyCount === 0
                Layout.fillWidth: true; Layout.fillHeight: true
                ColumnLayout {
                    anchors.centerIn: parent; spacing: 4
                    Components.Icon { source: "../icons/bell.svg"; color: Theme.fg4; iconSize: 24; Layout.alignment: Qt.AlignHCenter }
                    Text { text: "No notifications"; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }
                }
            }
            }
        }
    }
}
