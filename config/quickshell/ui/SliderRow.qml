import QtQuick
import QtQuick.Layouts
import qs
import qs.services as Sys

// [leading icon button or label] slider [caption]. `value` is passed down as a
// binding and never written: the slider shows its own in-drag value itself.
RowLayout {
    id: root

    property string label: ""
    property string icon: ""
    property color iconColor: Theme.textSecondary
    property bool iconInteractive: false
    property string caption: ""
    property bool suppressOsd: false

    property alias value: slider.value
    property alias minimum: slider.minimum
    property alias maximum: slider.maximum
    property alias pending: slider.pending
    property alias interactive: slider.interactive
    property alias claimsDrag: slider.claimsDrag
    readonly property alias shown: slider.shown

    signal iconClicked
    signal moved(real value)
    signal committed(real value)

    spacing: Metrics.s3

    Label {
        text: root.label
        role: "body"
        visible: root.label !== ""
        Layout.preferredWidth: 120
    }

    IconButton {
        name: root.icon
        iconColor: root.iconColor
        iconSize: Metrics.icon
        visible: root.icon !== ""
        interactive: root.iconInteractive
        onClicked: root.iconClicked()
    }

    Slider {
        id: slider
        Layout.fillWidth: true
        onMoved: value => root.moved(value)
        onCommitted: value => root.committed(value)
    }

    Label {
        text: root.caption
        role: "caption"
        numeric: true
        horizontalAlignment: Text.AlignRight
        Layout.preferredWidth: Metrics.s8 + Metrics.s2
    }

    // While the pointer owns the value, the OSD would be a second, worse copy of the control under the cursor.
    Binding {
        target: Sys.Osd
        property: "suppressed"
        value: true
        when: root.suppressOsd && slider.pressed
    }
}
