import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland
import qs
import qs.ui as Ui

// Width carries occupancy, colour carries focus. Nothing moves on hover: the
// row is a readout you glance at, and a readout that rearranges itself when the
// pointer crosses it is harder to read, not easier.
RowLayout {
    id: root

    readonly property int count: 9

    spacing: Metrics.s1

    Repeater {
        model: root.count

        Item {
            id: slot

            required property int index
            readonly property int id: slot.index + 1
            readonly property bool active: Hyprland.focusedWorkspace?.id === slot.id
            readonly property bool occupied: {
                const workspace = Hyprland.workspaces.values.find(candidate => candidate.id === slot.id);
                if (!workspace)
                    return false;
                return workspace.toplevels ? workspace.toplevels.values.length > 0 : true;
            }

            Layout.preferredWidth: pip.width
            Layout.preferredHeight: Metrics.barItemHeight

            Rectangle {
                id: pip
                anchors.centerIn: parent
                width: slot.active ? 20 : slot.occupied ? 12 : 8
                height: 8
                radius: 4
                antialiasing: true
                color: slot.active ? Theme.accent : pointer.containsMouse ? Theme.textSecondary : slot.occupied ? Theme.textTertiary : Theme.fillTrack

                Behavior on width {
                    Ui.Anim {
                        duration: Motion.quick
                        easing.bezierCurve: Motion.enter
                    }
                }
                Behavior on color {
                    Ui.Tint {
                        duration: Motion.quick
                    }
                }
            }

            MouseArea {
                id: pointer
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // `hl.dsp.workspace(n)` is not a dispatcher; it resolves to a
                // table and hyprctl reports the failure on stdout while exiting
                // zero, so the click silently does nothing.
                onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + slot.id + " })")
            }
        }
    }
}
