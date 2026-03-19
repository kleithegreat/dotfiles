import qs
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property string targetSsid

    spacing: 8

    Text { text: "Connecting to " + root.targetSsid + "\u2026"; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }

    Rectangle {
        Layout.alignment: Qt.AlignHCenter; width: 120; height: 4; radius: 2; color: Theme.bg3
        Rectangle {
            height: parent.height; radius: parent.radius; color: Theme.blueBright
            SequentialAnimation on width {
                loops: Animation.Infinite
                NumberAnimation { from: 0; to: 120; duration: 1200; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 120; to: 0; duration: 1200; easing.type: Easing.InOutQuad }
            }
        }
    }
}
