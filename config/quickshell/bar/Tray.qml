import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs
import qs.ui as Ui

// Tray icons stay in the tray, behind a disclosure. They belong to applications
// rather than to the shell, so their number and their artwork are outside our
// control; giving them a fixed, collapsed home keeps one badly-drawn icon from
// setting the width of the bar.
Row {
    id: root

    required property ShellState state

    property bool expanded: false

    spacing: 0
    visible: SystemTray.items.values.length > 0

    BarItem {
        anchors.verticalCenter: parent.verticalCenter
        contentWidth: Metrics.iconSm
        hint: root.expanded ? "Hide tray" : SystemTray.items.values.length + " tray items"
        onActivated: root.expanded = !root.expanded

        Ui.Icon {
            anchors.centerIn: parent
            name: "chevron-left"
            size: Metrics.iconSm
            color: root.expanded ? Theme.text : Theme.textTertiary
            rotation: root.expanded ? 180 : 0

            Behavior on rotation {
                Ui.Anim {
                    duration: Motion.quick
                    easing.bezierCurve: Motion.enter
                }
            }
        }
    }

    Item {
        anchors.verticalCenter: parent.verticalCenter
        height: Metrics.barItemHeight
        width: root.expanded ? icons.implicitWidth : 0
        clip: true

        Behavior on width {
            Ui.Anim {
                duration: Motion.settled
                easing.bezierCurve: Motion.enter
            }
        }

        Row {
            id: icons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0
            visible: root.expanded
            opacity: root.expanded ? 1 : 0

            Behavior on opacity {
                Ui.Anim {
                    duration: Motion.quick
                }
            }

            Repeater {
                model: SystemTray.items

                Ui.Pressable {
                    id: entry

                    required property SystemTrayItem modelData

                    implicitWidth: Metrics.barItemHeight
                    implicitHeight: Metrics.barItemHeight
                    radius: Metrics.rControl
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    pressScale: 0.9

                    function present() {
                        root.state.openMenu(entry.modelData.menu, entry.mapToItem(null, entry.width / 2, 0).x + Metrics.barMargin);
                    }

                    onClicked: {
                        if (entry.modelData.onlyMenu)
                            entry.present();
                        else
                            entry.modelData.activate();
                    }
                    onRightClicked: entry.present()

                    // An application naming an icon its theme does not carry is
                    // common, and the loader reports *Ready* for the theme's
                    // missing-icon placeholder — which Qt paints as a magenta
                    // checkerboard. Image status cannot detect this; the name
                    // has to be looked up before it is requested.
                    readonly property bool resolvable: {
                        const source = String(entry.modelData.icon || "");
                        if (source === "")
                            return false;
                        const themed = source.match(/^image:\/\/icon\/([^?]+)/);
                        if (!themed)
                            return true;
                        return Quickshell.iconPath(decodeURIComponent(themed[1]), true) !== "";
                    }

                    Image {
                        id: art
                        anchors.centerIn: parent
                        width: Metrics.iconSm
                        height: Metrics.iconSm
                        source: entry.resolvable ? entry.modelData.icon : ""
                        sourceSize.width: Math.round(Metrics.iconSm * Screen.devicePixelRatio)
                        sourceSize.height: Math.round(Metrics.iconSm * Screen.devicePixelRatio)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        visible: entry.resolvable && status === Image.Ready
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: Metrics.iconSm
                        height: Metrics.iconSm
                        radius: 3
                        color: Theme.fillActive
                        visible: !art.visible
                        antialiasing: true

                        Ui.Label {
                            anchors.centerIn: parent
                            text: (entry.modelData.title || entry.modelData.id || "?").charAt(0).toUpperCase()
                            role: "caption"
                            font.weight: Theme.weightSemi
                            color: Theme.textSecondary
                        }
                    }

                }
            }
        }
    }
}
