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
    visible: state.open_ || linger.running
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:overlay"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: state.open_ ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Everything below the bar dismisses on click; the bar strip is left out so
    // its buttons keep working while a surface is open. Without that hole, the
    // press that should toggle a surface closed is eaten by the overlay and the
    // click that follows re-opens it — which is what the old shell's 100ms
    // toggle debounce was really working around.
    mask: Region {
        x: 0
        y: Metrics.barHeight + Metrics.barMargin
        width: overlay.width
        height: Math.max(0, overlay.height - Metrics.barHeight - Metrics.barMargin)
    }

    Timer {
        id: linger
        interval: Motion.settled
        running: false
    }

    Connections {
        target: overlay.state

        function onCurrentChanged() {
            if (overlay.state.current === "")
                linger.restart();
        }
    }

    // The grab covers the bar as well, so pressing a bar button is not treated
    // as a click outside.
    HyprlandFocusGrab {
        active: overlay.state.open_
        windows: overlay.state.open_ ? [overlay, overlay.barWindow] : []
        onCleared: overlay.state.close()
    }

    Item {
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: overlay.state.close()
    }

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
