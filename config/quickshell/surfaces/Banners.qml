import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

PanelWindow {
    id: window

    readonly property int cardElevation: 30
    readonly property int pad: Metrics.shadowReach(cardElevation)

    anchors.top: true
    anchors.right: true
    margins.top: Metrics.detachment - pad
    // Flush to the screen edge; no shadow can be shown past it anyway.
    margins.right: 0
    implicitWidth: 380 + Metrics.gap + pad
    implicitHeight: Math.max(1, stack.implicitHeight + pad * 2)
    color: "transparent"
    visible: Sys.Notifications.banners.length > 0
    exclusionMode: ExclusionMode.Ignore
    // Only the cards take clicks; the shadow's margin is desktop.
    mask: Region {
        x: stack.x
        y: stack.y
        width: stack.width
        height: stack.height
    }
    WlrLayershell.namespace: "quickshell:banners"
    WlrLayershell.layer: WlrLayer.Overlay

    ColumnLayout {
        id: stack
        anchors.top: parent.top
        anchors.topMargin: window.pad
        anchors.right: parent.right
        anchors.rightMargin: Metrics.gap
        width: 380
        spacing: Metrics.s2

        Repeater {
            model: Sys.Notifications.banners

            Ui.Surface {
                id: card

                required property Notification modelData
                required property int index

                Layout.fillWidth: true
                Layout.preferredHeight: content.implicitHeight + Metrics.s4 * 2
                radius: Metrics.rPanel
                elevation: window.cardElevation

                opacity: 0
                // The layout owns x, so the arrival travels on a transform.
                property real slide: 60
                transform: Translate {
                    x: card.slide
                }

                Component.onCompleted: arrival.start()

                SequentialAnimation {
                    id: arrival
                    PauseAnimation {
                        duration: card.index * 40
                    }
                    ParallelAnimation {
                        Ui.Anim {
                            target: card
                            property: "opacity"
                            to: 1
                            duration: Motion.settled
                            easing.bezierCurve: Motion.enter
                        }
                        Ui.Anim {
                            target: card
                            property: "slide"
                            to: 0
                            duration: Motion.settled
                            easing.bezierCurve: Motion.enter
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: Sys.Notifications.dismiss(card.modelData)
                }

                ColumnLayout {
                    id: content
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Metrics.s4
                    spacing: 3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.s2

                        Ui.Label {
                            Layout.fillWidth: true
                            text: card.modelData.appName || "Notification"
                            role: "section"
                            elide: Text.ElideRight
                        }

                        Ui.Icon {
                            name: "close"
                            size: Metrics.iconSm - 2
                            color: Theme.textQuaternary
                        }
                    }

                    Ui.Label {
                        Layout.fillWidth: true
                        text: card.modelData.summary
                        role: "body"
                        font.weight: Theme.weightMedium
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        visible: text !== ""
                    }

                    Ui.Label {
                        Layout.fillWidth: true
                        text: card.modelData.body
                        role: "callout"
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                }
            }
        }
    }
}
