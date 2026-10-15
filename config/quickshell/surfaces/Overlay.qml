import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.ui as Ui

PanelWindow {
    id: overlay

    required property ShellState state
    required property var barWindow

    readonly property bool scrimmed: state.current === "settings"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    // One property owns visibility; see "one property nothing else can drive false" in docs/quickshell.md.
    property bool mapped: false
    visible: mapped
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: state.open_ ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // The bar strip is left out so its buttons keep working while a surface is open.
    mask: Region {
        x: 0
        y: Metrics.barHeight + Metrics.barMargin
        width: overlay.width
        height: Math.max(0, overlay.height - Metrics.barHeight - Metrics.barMargin)
    }

    // The overlay outlives the close by one exit animation, so the surface it
    // holds can play one.
    Timer {
        id: linger
        interval: Motion.settled
        onTriggered: overlay.mapped = false
    }

    Connections {
        target: overlay.state

        function onCurrentChanged() {
            if (overlay.state.open_) {
                linger.stop();
                overlay.mapped = true;
            } else {
                linger.restart();
            }
        }
    }

    // The grab covers the bar as well, so pressing a bar button is not treated
    // as a click outside.
    HyprlandFocusGrab {
        active: overlay.state.open_
        windows: overlay.state.open_ ? [overlay, overlay.barWindow] : []
        onCleared: overlay.state.close()
    }

    // Key events travel up from the focused item, so Escape must live on an ancestor of every surface.
    FocusScope {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: overlay.state.close()

        Rectangle {
            anchors.fill: parent
            color: Theme.scrim
            opacity: overlay.scrimmed ? 1 : 0
            visible: opacity > 0.001

            Behavior on opacity {
                Ui.Anim {
                    duration: overlay.scrimmed ? Motion.settled : Motion.quick
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onPressed: overlay.state.close()
        }

        ControlCenter {
            state: overlay.state
        }

        Calendar {
            state: overlay.state
        }

        NowPlaying {
            state: overlay.state
        }

        NotificationCenter {
            state: overlay.state
        }

        Session {
            state: overlay.state
        }

        TrayMenu {
            state: overlay.state
        }

        Settings {
            state: overlay.state
        }
    }
}
