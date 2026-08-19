import QtQuick
import QtQuick.Layouts
import qs

Rectangle {
    property int inset: 0

    Layout.fillWidth: true
    Layout.leftMargin: inset
    Layout.rightMargin: inset
    implicitHeight: Metrics.hairline
    color: Theme.separator
}
