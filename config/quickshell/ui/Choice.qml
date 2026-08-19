import QtQuick
import qs

// A bounded set of options rendered inline. A dropdown that hides four items
// behind a click is a menu built for a list that does not exist.
Row {
    id: root

    property var options: []
    property string current: ""
    property bool showsMissing: false

    signal picked(string value)

    spacing: Metrics.s1

    Repeater {
        model: root.options

        Pressable {
            id: option

            required property var modelData
            readonly property string value: modelData.value !== undefined ? modelData.value : modelData
            readonly property string label: modelData.label !== undefined ? modelData.label : modelData
            readonly property bool missing: root.showsMissing && !Catalog.available(option.value)

            implicitWidth: caption.implicitWidth + Metrics.s3 * 2
            implicitHeight: Metrics.controlHeight
            radius: Metrics.rControl
            active: root.current === option.value
            opacity: option.missing ? 0.4 : 1
            onClicked: root.picked(option.value)

            Label {
                id: caption
                anchors.centerIn: parent
                text: option.label
                role: "callout"
                font.weight: root.current === option.value ? Theme.weightMedium : Theme.weightRegular
                color: root.current === option.value ? Theme.text : Theme.textSecondary
            }
        }
    }
}
