import QtQuick
import QtQuick.Layouts
import qs

// A titled card of rows. Settings is nothing but these, which is what keeps
// fourteen panes written at different times looking like one application.
ColumnLayout {
    id: root

    property string title: ""
    property string footnote: ""

    default property alias rows: column.data

    Layout.fillWidth: true
    spacing: Metrics.s1

    Label {
        text: root.title
        role: "section"
        Layout.leftMargin: Metrics.s3
        visible: text !== ""
    }

    Card {
        Layout.fillWidth: true
        implicitHeight: column.implicitHeight + Metrics.s1 * 2

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Metrics.s1
            spacing: 0
        }
    }

    Label {
        text: root.footnote
        role: "caption"
        Layout.fillWidth: true
        Layout.leftMargin: Metrics.s3
        Layout.topMargin: 2
        wrapMode: Text.WordWrap
        visible: text !== ""
    }
}
