import QtQuick
import QtQuick.Layouts
import qs

// Left, right and case charge as rings, the way an iPhone's batteries widget
// shows them. A part that is not reporting — a pod out of reach, a case far
// away — is absent rather than shown empty.
RowLayout {
    id: root

    property var battery: null

    spacing: Metrics.s5

    Repeater {
        model: [
            { key: "left", icon: "pod-left" },
            { key: "right", icon: "pod-right" },
            { key: "case", icon: "airpods-case" }
        ]

        ColumnLayout {
            id: part

            required property var modelData
            readonly property var cell: root.battery ? root.battery[part.modelData.key] ?? null : null
            readonly property int level: part.cell?.level ?? 0

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            visible: part.cell !== null
            spacing: Metrics.s2

            Ring {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 52
                implicitHeight: 52
                thickness: 4
                fraction: part.level / 100
                color: part.cell?.charging ? Theme.positive : part.level <= 20 ? Theme.critical : Theme.text

                Icon {
                    anchors.centerIn: parent
                    name: part.modelData.icon
                    size: Metrics.iconLg
                    color: Theme.textSecondary
                }
            }

            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: part.level + "%"
                role: "caption"
                numeric: true
                color: part.cell?.charging ? Theme.positive : Theme.textSecondary
            }
        }
    }
}
