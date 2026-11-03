import QtQuick
import QtQuick.Layouts
import qs

// Left, right and case charge side by side. A part that is not reporting —
// a pod out of reach, a case far away — is absent rather than shown empty.
RowLayout {
    id: root

    property var battery: null

    spacing: Metrics.s4

    Repeater {
        model: [
            { key: "left", label: "Left", icon: "airpods" },
            { key: "right", label: "Right", icon: "airpods" },
            { key: "case", label: "Case", icon: "airpods-case" }
        ]

        ColumnLayout {
            id: part

            required property var modelData
            readonly property var cell: root.battery ? root.battery[part.modelData.key] ?? null : null

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: part.cell !== null
            spacing: Metrics.s1

            RowLayout {
                Layout.fillWidth: true
                spacing: Metrics.s1

                Icon {
                    name: part.modelData.icon
                    size: Metrics.iconSm
                    color: Theme.textSecondary
                }

                Label {
                    Layout.fillWidth: true
                    text: part.modelData.label
                    role: "caption"
                }

                Label {
                    text: (part.cell?.level ?? 0) + "%"
                    role: "caption"
                    numeric: true
                    color: part.cell?.charging ? Theme.positive : Theme.textSecondary
                }
            }

            Meter {
                Layout.fillWidth: true
                fraction: (part.cell?.level ?? 0) / 100
                fill: part.cell?.charging ? Theme.positive : (part.cell?.level ?? 100) <= 20 ? Theme.critical : Theme.text
            }
        }
    }
}
