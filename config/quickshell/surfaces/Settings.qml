import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

// One surface, one sidebar, one content column. The old settings drew the
// sidebar and the content as two separate floating panels with a seam down the
// middle and a list that clipped mid-row at the bottom edge — two objects
// pretending to be one window.
Item {
    id: root

    required property ShellState state

    anchors.fill: parent
    visible: state.isOpen("settings") || panel.opacity > 0.001

    readonly property var sections: [
        {
            title: "System",
            items: [
                { id: "Network", label: "Network", icon: "wifi", shown: true },
                { id: "Bluetooth", label: "Bluetooth", icon: "bluetooth-on", shown: Sys.Bluetooth.available },
                { id: "Sound", label: "Sound", icon: "volume-high", shown: true },
                { id: "Display", label: "Displays", icon: "monitor", shown: true },
                { id: "Notifications", label: "Notifications", icon: "bell", shown: true },
                { id: "Power", label: "Battery & Power", icon: "bolt", shown: Sys.Host.battery || Sys.Host.profileSwitching }
            ]
        },
        {
            title: "Appearance",
            items: [
                { id: "Theme", label: "Theme", icon: "palette", shown: true },
                { id: "Wallpaper", label: "Wallpaper", icon: "photo", shown: true },
                { id: "Typography", label: "Typography", icon: "typography", shown: true },
                { id: "Pointer", label: "Pointer & Icons", icon: "cursor", shown: true }
            ]
        },
        {
            title: "Desktop",
            items: [
                { id: "Window", label: "Windows", icon: "layout", shown: true },
                { id: "ScreenTime", label: "Screen Time", icon: "hourglass", shown: true },
                { id: "Security", label: "Fingerprint", icon: "certificate", shown: Sys.Host.fingerprint }
            ]
        }
    ]

    Ui.Surface {
        id: panel

        anchors.centerIn: parent
        width: 780
        height: 560
        radius: Metrics.rPanel
        tint: Theme.glassPanel
        elevation: 48

        opacity: root.state.isOpen("settings") ? 1 : 0
        layer.enabled: rise.running
        property real emerge: root.state.isOpen("settings") ? 1 : Motion.emergeScale
        transform: Scale {
            xScale: panel.emerge
            yScale: panel.emerge
            origin.x: panel.width / 2
            origin.y: panel.height / 2
        }

        Behavior on emerge {
            Ui.Anim {
                id: rise
                duration: Motion.settled
                easing.bezierCurve: root.state.isOpen("settings") ? Motion.enter : Motion.exit
            }
        }
        Behavior on opacity {
            Ui.Anim {
                duration: Motion.quick
            }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ── Sidebar ────────────────────────────────────────────────────
            Item {
                Layout.preferredWidth: 208
                Layout.fillHeight: true

                Ui.Scroll {
                    anchors.fill: parent
                    anchors.margins: Metrics.s2
                    anchors.topMargin: Metrics.s3
                    contentHeight: nav.height
                    indicator: false

                    ColumnLayout {
                        id: nav
                        width: parent.width
                        spacing: Metrics.s3

                        Repeater {
                            model: root.sections

                            ColumnLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: 1

                                Ui.Label {
                                    text: parent.modelData.title
                                    role: "section"
                                    Layout.leftMargin: Metrics.rowInset
                                    Layout.bottomMargin: 2
                                }

                                Repeater {
                                    model: parent.modelData.items

                                    Ui.ListRow {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        visible: modelData.shown
                                        icon: modelData.icon
                                        title: modelData.label
                                        selected: root.state.pane === modelData.id
                                        onClicked: root.state.pane = modelData.id
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    anchors.topMargin: Metrics.s3
                    anchors.bottomMargin: Metrics.s3
                    width: Metrics.hairline
                    color: Theme.separator
                }
            }

            // ── Content ────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Metrics.s5
                    spacing: Metrics.s4

                    RowLayout {
                        Layout.fillWidth: true

                        Ui.Label {
                            text: root.paneTitle
                            role: "title"
                            Layout.fillWidth: true
                        }

                        Ui.Pressable {
                            implicitWidth: Metrics.s6
                            implicitHeight: Metrics.s6
                            radius: Metrics.rPill
                            onClicked: root.state.close()

                            Ui.Icon {
                                anchors.centerIn: parent
                                name: "close"
                                size: Metrics.iconSm
                                color: Theme.textTertiary
                            }
                        }
                    }

                    Loader {
                        id: pane
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        asynchronous: true
                        source: Qt.resolvedUrl("settings/" + root.state.pane + "Pane.qml")

                        // Panes cross-fade rather than cutting, so switching
                        // reads as one surface changing its mind.
                        opacity: status === Loader.Ready ? 1 : 0
                        Behavior on opacity {
                            Ui.Anim {
                                duration: Motion.instant
                            }
                        }
                    }
                }
            }
        }
    }

    readonly property string paneTitle: {
        for (let s = 0; s < sections.length; s++) {
            for (let i = 0; i < sections[s].items.length; i++) {
                if (sections[s].items[i].id === state.pane)
                    return sections[s].items[i].label;
            }
        }
        return "Settings";
    }
}
