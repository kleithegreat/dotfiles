import qs
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property var channelModel
    required property string currentChannel
    required property string currentBand
    required property bool scanning

    spacing: 8

    Text {
        visible: root.currentChannel !== ""
        text: "You're on channel " + root.currentChannel + " (" + root.currentBand + " GHz)"
        color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
    }

    Rectangle { Layout.fillWidth: true; height: 1; color: Theme.bg3 }

    // ── Skeleton loading ──
    Column {
        visible: root.scanning
        Layout.fillWidth: true
        spacing: 0

        Repeater {
            model: ListModel {
                ListElement { skelWidth: 120 }
                ListElement { skelWidth: 150 }
                ListElement { skelWidth: 100 }
                ListElement { skelWidth: 140 }
                ListElement { skelWidth: 110 }
            }
            delegate: Item {
                required property int skelWidth
                required property int index
                width: parent.width; height: 52
                ColumnLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 8; anchors.rightMargin: 8
                    spacing: 6

                    RowLayout { spacing: 6
                        Rectangle { width: 36; height: 10; radius: 5; color: Theme.bg3 }
                        Rectangle { width: 40; height: 10; radius: 5; color: Theme.bg3 }
                        Item { Layout.fillWidth: true }
                        Rectangle { width: 65; height: 10; radius: 5; color: Theme.bg3 }
                    }
                    Rectangle { width: skelWidth; height: 8; radius: 4; color: Theme.bg3 }
                }

                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    PauseAnimation { duration: index * 120 }
                    NumberAnimation { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                }
            }
        }
    }

    Flickable {
        visible: !root.scanning
        Layout.fillWidth: true; Layout.preferredHeight: Math.min(channelCol.implicitHeight, 300)
        Layout.maximumHeight: 300
        contentHeight: channelCol.implicitHeight; clip: true; boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: channelCol; width: parent.width; spacing: 8

            Repeater {
                model: root.channelModel
                Rectangle {
                    required property int channel
                    required property string band
                    required property string networks
                    required property int count
                    required property bool isOurs
                    Layout.fillWidth: true
                    height: chanItemCol.implicitHeight + 16; radius: Theme.hoverRadius
                    color: isOurs ? Qt.rgba(Theme.blueBright.r, Theme.blueBright.g, Theme.blueBright.b, 0.1) : "transparent"
                    border.width: isOurs ? 1 : 0; border.color: Theme.blueBright

                    ColumnLayout {
                        id: chanItemCol
                        anchors.fill: parent; anchors.margins: 8; spacing: 3

                        RowLayout { spacing: 6
                            Text {
                                text: "Ch " + channel
                                color: isOurs ? Theme.blueBright : Theme.fg
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                            }
                            Rectangle {
                                width: chanBandBadge.implicitWidth + 6; height: 14; radius: 3
                                color: Theme.bg2; border.width: 1; border.color: Theme.bg3
                                Text { id: chanBandBadge; anchors.centerIn: parent; text: band + " GHz"
                                    color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 3 }
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: count === 1 ? "1 network" : count + " networks"
                                color: count <= 2 ? Theme.greenBright : (count <= 5 ? Theme.yellowBright : Theme.redBright)
                                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                            }
                        }
                        Text {
                            text: networks; color: Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 2
                            wrapMode: Text.WordWrap; Layout.fillWidth: true
                            maximumLineCount: 2; elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    Text {
        visible: root.currentChannel !== ""
        text: {
            for (let i = 0; i < root.channelModel.count; i++) {
                let item = root.channelModel.get(i);
                if (item.isOurs) {
                    if (item.count <= 2) return "Your channel looks clear.";
                    if (item.count <= 5) return "Your channel is moderately congested. Consider switching to a less crowded channel in your router settings.";
                    return "Your channel is very congested (" + item.count + " networks). Switching channels in your router settings would likely improve performance.";
                }
            }
            return "";
        }
        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
        wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.topMargin: 2
    }
}
