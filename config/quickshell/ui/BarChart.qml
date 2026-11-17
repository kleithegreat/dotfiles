import QtQuick
import qs

// Bars over a time axis with gridlines, after macOS's battery charts.
Item {
    id: root

    // Each a fraction of the plot height, or null for no bar.
    property var values: []
    // Per-bar colours; `fill` where absent.
    property var tints: []
    property color fill: Theme.accent
    // Bars whose column is washed in `shade`, such as time on the charger.
    property var shaded: []
    property color shade: Theme.withAlpha(Theme.positive, 0.16)
    // Gridline labels, top to bottom, evenly spaced.
    property var yLabels: []
    // `{ at, text }`, `at` a fraction of the width.
    property var xLabels: []

    implicitHeight: 128

    readonly property real _slot: plot.width / Math.max(1, values.length)
    readonly property real _gap: Math.max(1, Math.round(_slot * 0.22))

    Item {
        id: plot
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: Metrics.s1
        anchors.rightMargin: root.yLabels.length > 0 ? Metrics.s8 + Metrics.s1 : 0
        anchors.bottomMargin: Theme.sizeCaption + Metrics.s2

        Repeater {
            model: root.values.length

            Rectangle {
                required property int index

                x: index * root._slot
                width: Math.ceil(root._slot)
                height: plot.height
                color: root.shade
                visible: root.shaded[index] === true
            }
        }

        Repeater {
            model: root.yLabels.length

            Item {
                required property int index

                width: plot.width
                y: root.yLabels.length < 2 ? 0 : index / (root.yLabels.length - 1) * plot.height

                Rectangle {
                    width: parent.width
                    height: Metrics.hairline
                    color: Theme.separator
                }

                Label {
                    x: parent.width + Metrics.s1
                    anchors.verticalCenter: parent.top
                    text: root.yLabels[parent.index] ?? ""
                    role: "caption"
                    numeric: true
                }
            }
        }

        // Keyed on the count, never the array, so heights animate across updates.
        Repeater {
            model: root.values.length

            Rectangle {
                required property int index
                readonly property var value: root.values[index]

                x: index * root._slot + root._gap / 2
                anchors.bottom: parent.bottom
                width: Math.max(1, root._slot - root._gap)
                height: value === null || value === undefined ? 0 : Math.max(2, plot.height * Math.min(1, value))
                radius: Math.min(width / 2, 2)
                color: root.tints[index] ?? root.fill
                antialiasing: true

                Behavior on height {
                    Anim {
                        duration: Motion.settled
                    }
                }
            }
        }
    }

    Repeater {
        model: root.xLabels.length

        Label {
            required property int index

            x: plot.width * (root.xLabels[index]?.at ?? 0)
            anchors.bottom: parent.bottom
            text: root.xLabels[index]?.text ?? ""
            role: "caption"
        }
    }
}
