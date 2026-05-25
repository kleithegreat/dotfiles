import qs
import QtQuick
import QtQuick.Layouts
import "components" as Components

FocusScope {
    id: drawer

    property bool active: false
    property bool closing: false
    signal close()

    readonly property bool overlayVisible: active || closing
    readonly property Item panelItem: panel
    readonly property Item focusTarget: drawer
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    readonly property real availableHeight: Math.max(0, height - Theme.popupTopMargin - Theme.gapOut)
    readonly property string historyLabel: NotificationService.historyCount === 0
        ? "No notifications"
        : NotificationService.historyCount === 1
            ? "1 notification"
            : NotificationService.historyCount + " notifications"

    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem
    Keys.onEscapePressed: drawer.close()

    function prepareForOpen() {
        panel.opacity = 0;
        panel.scale = Theme.popupStartScale;
    }

    onActiveChanged: {
        if (active) {
            closeAnimation.stop();
            closing = false;
            forceActiveFocus();
            prepareForOpen();
            openAnimation.restart();
            return;
        }

        if (!closing) {
            openAnimation.stop();
            closing = true;
            closeAnimation.restart();
        }
    }

    SequentialAnimation {
        id: openAnimation

        ParallelAnimation {
            Components.Anim {
                target: panel
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }

            SequentialAnimation {
                PauseAnimation { duration: Theme.animPopupScaleLead }

                Components.Anim {
                    target: panel
                    property: "scale"
                    to: 1
                    duration: Math.max(0, Theme.animPopupIn - Theme.animPopupScaleLead)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveEmphasizedEnter
                }
            }
        }
    }

    SequentialAnimation {
        id: closeAnimation

        ParallelAnimation {
            Components.Anim {
                target: panel
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }

            Components.Anim {
                target: panel
                property: "scale"
                to: Theme.popupStartScale
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }

        ScriptAction {
            script: drawer.closing = false
        }
    }

    component IconButton: Rectangle {
        id: iconButton

        property string source: ""
        property bool danger: false
        signal clicked()

        implicitWidth: 28
        implicitHeight: 28
        radius: Theme.btnRadius
        color: "transparent"
        scale: buttonArea.pressed ? 0.94 : 1
        transformOrigin: Item.Center

        Behavior on scale { Components.Anim { duration: Theme.animMicro } }

        Components.HoverLayer {
            id: buttonArea
            anchors.fill: parent
            radius: iconButton.radius
            color: Theme.bg2
            hoverOpacity: 0.7
            pressedOpacity: 0.9
            pressedScale: 1
            onClicked: iconButton.clicked()
        }

        Components.Icon {
            anchors.centerIn: parent
            source: iconButton.source
            iconSize: Theme.fontSizeSmall + 3
            color: buttonArea.containsMouse && iconButton.danger ? Theme.redBright : Theme.fg4

            Behavior on color { Components.CAnim { duration: Theme.animHover } }
        }
    }

    Rectangle {
        id: panel

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Theme.popupTopMargin
        anchors.rightMargin: Theme.gapOut
        width: Theme.drawerWidth
        height: Math.min(560, drawer.availableHeight)
        radius: Theme.popupRadius
        color: Theme.bg1
        border.width: 1
        border.color: Theme.bg3
        opacity: 0
        scale: Theme.popupStartScale
        clip: true
        transformOrigin: Item.TopRight
        layer.enabled: openAnimation.running || closeAnimation.running
        layer.smooth: true

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.popupPadding
            spacing: Theme.sectionSpacing

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Components.Icon {
                    source: NotificationService.doNotDisturb ? "icons/bell-off.svg" : "icons/bell.svg"
                    color: NotificationService.doNotDisturb ? Theme.orangeBright : Theme.fg
                    iconSize: Theme.fontSizeLarge
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    Text {
                        text: "Notifications"
                        color: Theme.fg
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.headerFontSize
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Text {
                        text: drawer.historyLabel
                        color: Theme.fg4
                        font.family: Theme.systemFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                    }
                }

                Components.ActionButton {
                    visible: NotificationService.historyCount > 0
                    text: "Clear"
                    baseColor: "transparent"
                    hoverColor: Theme.bg2
                    borderColor: "transparent"
                    textColor: Theme.redBright
                    onClicked: NotificationService.clearHistory()
                }

                IconButton {
                    source: "icons/close.svg"
                    onClicked: drawer.close()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.bg3
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: dndRow.implicitHeight + Theme.notifPadding
                radius: Theme.btnRadius
                color: Theme.bg0_h
                border.width: 1
                border.color: Theme.bg3

                RowLayout {
                    id: dndRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Theme.notifPadding / 2
                    anchors.rightMargin: Theme.notifPadding / 2
                    spacing: 8

                    Components.Icon {
                        source: NotificationService.doNotDisturb ? "icons/bell-off.svg" : "icons/bell.svg"
                        color: NotificationService.doNotDisturb ? Theme.orangeBright : Theme.fg4
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: "Do Not Disturb"
                            color: Theme.fg
                            font.family: Theme.systemFamily
                            font.pixelSize: Theme.fontSizeSmall
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Text {
                            text: NotificationService.doNotDisturb
                                ? "Popups are muted. History is still saved."
                                : "Popups are shown and saved to history."
                            color: Theme.fg4
                            font.family: Theme.systemFamily
                            font.pixelSize: Theme.fontSizeSmall - 1
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                        }
                    }

                    Components.ToggleSwitch {
                        checked: NotificationService.doNotDisturb
                        onToggled: NotificationService.toggleDnd()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120

                Components.WheelFlickable {
                    anchors.fill: parent
                    visible: NotificationService.historyCount > 0
                    contentWidth: width
                    contentHeight: historyColumn.implicitHeight
                    clip: true

                    Column {
                        id: historyColumn
                        width: parent.width
                        spacing: Theme.notifSpacing

                        Repeater {
                            model: NotificationService.historyModel

                            Rectangle {
                                id: card

                                required property int entryId
                                required property int nid
                                required property string appName
                                required property string summary
                                required property string body
                                required property string timeStr

                                width: historyColumn.width
                                height: cardContent.implicitHeight + Theme.notifPadding
                                radius: Theme.btnRadius
                                color: Theme.bg2
                                border.width: 1
                                border.color: Theme.bg3

                                ColumnLayout {
                                    id: cardContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Theme.notifPadding / 2
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Text {
                                            text: card.appName
                                            color: Theme.fg4
                                            font.family: Theme.systemFamily
                                            font.pixelSize: Theme.fontSizeSmall - 1
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: card.timeStr
                                            visible: text !== ""
                                            color: Theme.fg4
                                            font.family: Theme.systemFamily
                                            font.pixelSize: Theme.fontSizeSmall - 2
                                        }

                                        IconButton {
                                            source: "icons/close.svg"
                                            danger: true
                                            implicitWidth: 22
                                            implicitHeight: 22
                                            onClicked: NotificationService.removeHistoryEntry(card.entryId)
                                        }
                                    }

                                    Text {
                                        text: card.summary !== "" ? card.summary : "Notification"
                                        color: Theme.fg
                                        font.family: Theme.systemFamily
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        wrapMode: Text.WordWrap
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        visible: card.body !== ""
                                        text: card.body
                                        color: Theme.fg3
                                        font.family: Theme.systemFamily
                                        font.pixelSize: Theme.fontSizeSmall - 1
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                        textFormat: Text.PlainText
                                        Layout.fillWidth: true
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    visible: NotificationService.historyCount === 0

                    ColumnLayout {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, 260)
                        spacing: 6

                        Components.Icon {
                            source: "icons/bell.svg"
                            color: Theme.fg4
                            iconSize: 26
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Text {
                            text: "No notifications"
                            color: Theme.fg
                            font.family: Theme.systemFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "New notifications will appear here after they arrive."
                            color: Theme.fg4
                            font.family: Theme.systemFamily
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            horizontalAlignment: Text.AlignHCenter
                            Layout.fillWidth: true
                        }
                    }
                }
            }
        }
    }
}
