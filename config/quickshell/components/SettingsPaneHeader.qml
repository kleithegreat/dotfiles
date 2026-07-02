import QtQuick
import QtQuick.Layouts
import ".." as Root

ColumnLayout {
    id: root

    required property string title
    required property string iconSource
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        Icon {
            source: root.iconSource
            color: Root.Theme.fg
        }

        Text {
            text: root.title
            color: Root.Theme.fg
            font.family: Root.Theme.fontFamily
            font.pixelSize: Root.Theme.headerFontSize
            font.bold: true
            Layout.fillWidth: true
        }

        RowLayout {
            id: actionRow
            spacing: 6
        }
    }

    Divider {}
}
