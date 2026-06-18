import QtQuick
import QtQuick.Layouts
import ".." as Root

// Horizontal hairline separator for vertical layouts (ColumnLayout children).
Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    height: 1
    color: Root.Theme.bg3
}
