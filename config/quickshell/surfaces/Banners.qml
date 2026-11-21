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

        property var _animatedIds: ({})

        function hasAnimated(id) {
            return _animatedIds[id] === true;
        }

        function markAnimated(id) {
            const next = Object.assign({}, _animatedIds);
            next[id] = true;
            _animatedIds = next;
        }

        Repeater {
            // Keyed on count so adding/dismissing one banner doesn't replay arrivals on siblings.
            model: Sys.Notifications.banners.length

            Ui.Surface {
                id: card

                required property int index
                readonly property Notification item: Sys.Notifications.banners[card.index] ?? null
                readonly property int notifId: item ? item.id : -1

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

                function _syncArrival() {
                    if (notifId < 0)
                        return;
                    if (!stack.hasAnimated(notifId)) {
                        stack.markAnimated(notifId);
                        slide = 60;
                        opacity = 0;
                        arrival.restart();
                    } else {
                        arrival.stop();
                        slide = 0;
                        opacity = 1;
                    }
                }

                Component.onCompleted: _syncArrival()
                onNotifIdChanged: _syncArrival()

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
                            easing.bezierCurve: Motion.standard
                        }
                        Ui.Anim {
                            target: card
                            property: "slide"
                            to: 0
                            duration: Motion.settled
                            easing.bezierCurve: Motion.spring
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: Sys.Notifications.dismiss(card.item)
                }

                ColumnLayout {
                    id: content
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Metrics.s4
                    spacing: Metrics.s2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Metrics.s3

                        Ui.Card {
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            Layout.alignment: Qt.AlignTop
                            radius: Metrics.rControl
                            clip: true
                            visible: (card.item?.image ?? "") !== ""

                            Image {
                                anchors.fill: parent
                                source: card.item?.image ?? ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                smooth: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Metrics.s2

                                Ui.Label {
                                    Layout.fillWidth: true
                                    text: card.item?.appName || "Notification"
                                    role: "section"
                                    elide: Text.ElideRight
                                }

                                Ui.Icon {
                                    name: "close"
                                    size: Metrics.iconSm
                                    color: Theme.textQuaternary
                                }
                            }

                            Ui.Label {
                                Layout.fillWidth: true
                                text: card.item?.summary ?? ""
                                role: "body"
                                font.weight: Theme.weightMedium
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                visible: text !== ""
                            }

                            Ui.Label {
                                Layout.fillWidth: true
                                text: card.item?.body ?? ""
                                role: "callout"
                                wrapMode: Text.WordWrap
                                maximumLineCount: 3
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: Metrics.s1
                        visible: (card.item?.actions?.length ?? 0) > 0

                        Repeater {
                            model: card.item?.actions ?? []

                            Ui.Button {
                                required property var modelData
                                text: modelData.text
                                onClicked: modelData.invoke()
                            }
                        }
                    }
                }
            }
        }
    }
}
