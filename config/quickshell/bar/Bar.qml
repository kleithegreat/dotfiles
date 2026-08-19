import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

PanelWindow {
    id: bar

    required property ShellState state

    anchors {
        top: true
        left: true
        right: true
    }
    margins {
        top: Metrics.barMargin - Metrics.barShadowPad
        left: Metrics.barMargin - Metrics.barShadowPad
        right: Metrics.barMargin - Metrics.barShadowPad
    }
    implicitHeight: Metrics.barHeight + Metrics.barShadowPad * 2
    // Layer-shell adds the surface's own margin to the exclusive zone, so the
    // two together must come to the margin plus the bar — never the margin
    // twice, which leaves double the air below the bar that sits above it.
    exclusiveZone: Metrics.barHeight + Metrics.barShadowPad
    color: "transparent"
    WlrLayershell.namespace: "quickshell:bar"

    Ui.Surface {
        id: plate
        anchors.fill: parent
        anchors.margins: Metrics.barShadowPad
        // Follows Hyprland's window rounding and its shadow, so the bar is cut
        // from the same shape language as everything tiled beneath it — an
        // identical gap reads wider around a plate that casts nothing.
        radius: Sys.Appearance.value("hypr_rounding", Metrics.rBar)
        tint: Theme.glassBar
        elevation: 9

        Clock {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            hint: "Calendar and weather"
            surface: "calendar"
            onMoved: (name, at) => bar.state.setOrigin(name, at)
            onActivated: anchor => bar.state.open("calendar", anchor)
        }

        RowLayout {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Metrics.barInset
            spacing: Metrics.barSpacing

            RowLayout {
                spacing: Metrics.barSpacing

                Workspaces {}

                Glyph {
                    icon: "layout"
                    hint: "Workspace overview"
                    // hyprexpo's expo() returns nil, so the IPC needs a real
                    // dispatcher handed back to it.
                    onActivated: Hyprland.dispatch('(function() hl.plugin.hyprexpo.expo("toggle") return hl.dsp.no_op() end)()')
                }
            }

            NowPlaying {
                hint: "Now playing"
                surface: "media"
                onMoved: (name, at) => bar.state.setOrigin(name, at)
                onActivated: anchor => bar.state.open("media", anchor)
            }
        }

        RowLayout {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Metrics.barInset
            spacing: Metrics.barSpacing

            Tray {
                Layout.alignment: Qt.AlignVCenter
                state: bar.state
            }

            RowLayout {
                spacing: 2

                Status {
                    surface: "control"
                    onMoved: (name, at) => bar.state.setOrigin(name, at)
                    hint: Sys.Network.label + " · " + Sys.Audio.percent + "% volume" + (Sys.Power.present ? " · " + Sys.Power.percent + "% battery" : "")
                    onActivated: anchor => bar.state.open("control", anchor)
                }

                Glyph {
                    icon: Sys.Notifications.dnd ? "bell-off" : "bell"
                    badge: Sys.Notifications.historyCount > 0 && !Sys.Notifications.dnd
                    surface: "notifications"
                    onMoved: (name, at) => bar.state.setOrigin(name, at)
                    hint: Sys.Notifications.dnd ? "Do Not Disturb" : Sys.Notifications.historyCount > 0 ? Sys.Notifications.historyCount + " notifications" : "Notifications"
                    tint: Sys.Notifications.dnd ? Theme.textQuaternary : hovered ? Theme.text : Theme.textSecondary
                    onActivated: anchor => bar.state.open("notifications", anchor)
                }

                Glyph {
                    icon: "power"
                    surface: "session"
                    onMoved: (name, at) => bar.state.setOrigin(name, at)
                    hint: "Session"
                    tint: hovered ? Theme.critical : Theme.textSecondary
                    onActivated: anchor => bar.state.open("session", anchor)
                }
            }
        }
    }
}
