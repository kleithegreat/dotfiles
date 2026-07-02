import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

FocusScope {
    id: root
    anchors.fill: parent

    readonly property string popupState: {
        if (BluetoothService.connecting) return "connecting";
        if (BluetoothService.connectError !== "") return "error";
        return "list";
    }
    readonly property bool listStateResolved: popupState === "list" && BluetoothService.powerStateKnown
    readonly property bool deviceListLoading: root.listStateResolved
        && BluetoothService.powered
        && BluetoothService.pairedModel.count === 0
        && BluetoothService.discoveredModel.count === 0
        && (BluetoothService.refreshing || BluetoothService.scanning)

    Component.onCompleted: {
        BluetoothService.clearConnectError();
        BluetoothService.refresh(true);
    }

    onPopupStateChanged: {
        if (popupState === "error")
            errorTimer.restart();
    }

    Timer {
        id: errorTimer; interval: 2000
        onTriggered: BluetoothService.clearConnectError()
    }

    component DeviceRow: Rectangle {
        id: deviceRow
        required property string mac
        required property string name
        property color iconColor: Theme.fg

        Layout.fillWidth: true; height: 30; radius: Theme.hoverRadius; color: "transparent"

        Rectangle {
            anchors.fill: parent; radius: parent.radius; color: Theme.bg2
            opacity: deviceArea.pressed ? 0.9 : (deviceArea.containsMouse ? 0.6 : 0)
            Behavior on opacity { Components.StdAnim { duration: Theme.animHover } }
        }
        scale: deviceArea.pressed ? 0.98 : 1.0
        Behavior on scale { Components.StdAnim { duration: Theme.animMicro } }
        transformOrigin: Item.Center

        Components.Icon {
            id: deviceIcon
            anchors.left: parent.left; anchors.leftMargin: Theme.listItemPadding; anchors.verticalCenter: parent.verticalCenter
            source: "../icons/bluetooth-on.svg"; color: deviceRow.iconColor
        }
        Text {
            anchors.left: deviceIcon.right; anchors.leftMargin: 6
            anchors.right: deviceConnect.left; anchors.rightMargin: 6; anchors.verticalCenter: parent.verticalCenter
            text: deviceRow.name; color: Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight
        }
        Text {
            id: deviceConnect
            anchors.right: parent.right; anchors.rightMargin: Theme.listItemPadding; anchors.verticalCenter: parent.verticalCenter
            text: "Connect"; color: deviceArea.containsMouse ? Theme.blueBright : Theme.fg4
            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
        }
        Components.HoverLayer { id: deviceArea; flat: true
            onClicked: BluetoothService.connectDevice(deviceRow.mac, deviceRow.name) }
    }

    Components.WheelFlickable {
        anchors.fill: parent
        contentHeight: btCol.implicitHeight
        clip: true

        ColumnLayout {
            id: btCol
            width: parent.width
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true

                Components.Icon { source: "../icons/bluetooth-on.svg"; color: Theme.fg }
                Text {
                    text: "Bluetooth"
                    color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.headerFontSize; font.bold: true
                    Layout.fillWidth: true; elide: Text.ElideRight
                }

                Rectangle {
                    visible: root.listStateResolved && BluetoothService.powered
                    width: scanLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: scanA; color: Theme.bg2; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                        onClicked: { if (!BluetoothService.scanning) BluetoothService.startScan(); }
                        Text { id: scanLabel; anchors.centerIn: parent
                            text: BluetoothService.scanning ? "Scanning…" : "Scan"
                            color: scanA.containsMouse ? Theme.blueBright : Theme.fg4
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text { text: "Power"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.fillWidth: true }
                Components.ToggleSwitch {
                    checked: BluetoothService.powered
                    disabled: BluetoothService.powerBusy
                    pending: BluetoothService.powerBusy
                    onToggled: BluetoothService.togglePower()
                }
            }

            Components.Divider {}

            // Powered off empty state

            Item {
                visible: root.listStateResolved && !BluetoothService.powered
                Layout.fillWidth: true; implicitHeight: 40
                Text { anchors.centerIn: parent; text: "Bluetooth is off"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            }

            // Connected device
            Item {
                visible: root.listStateResolved && BluetoothService.powered && BluetoothService.connectedName !== ""
                Layout.fillWidth: true; implicitHeight: 30

                Rectangle { id: connAccent; width: 3; height: parent.height; radius: 1.5; color: Theme.greenBright
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter }

                Text {
                    anchors.left: connAccent.right; anchors.leftMargin: 8
                    anchors.right: connBattText.visible ? connBattText.left : connDcBtn.left
                    anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: BluetoothService.connectedName; color: Theme.greenBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight
                }

                Text {
                    id: connBattText; visible: BluetoothService.connectedBattery >= 0
                    anchors.right: connDcBtn.left; anchors.rightMargin: 8; anchors.verticalCenter: parent.verticalCenter
                    text: BluetoothService.connectedBattery + "%"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini
                }

                Rectangle {
                    id: connDcBtn
                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                    width: connDcLabel.implicitWidth + Theme.btnPaddingH * 2; height: Theme.btnHeight; radius: Theme.btnRadius
                    color: "transparent"
                    Components.HoverLayer {
                        id: connDcA; color: Theme.bg2; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                        disabled: BluetoothService.disconnectBusy
                        onClicked: BluetoothService.disconnectDevice()
                        Text { id: connDcLabel; anchors.centerIn: parent; text: BluetoothService.disconnectBusy ? "Disconnecting…" : "Disconnect"
                            color: connDcA.containsMouse ? Theme.redBright : Theme.fg4
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                    }
                }
            }

            // Error message
            Item {
                Layout.fillWidth: true; visible: BluetoothService.connectError !== ""
                implicitHeight: btErrorText.implicitHeight
                Text { id: btErrorText; width: parent.width
                    text: BluetoothService.connectError; color: Theme.redBright
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap
                }
            }

            // Device list
            ColumnLayout {
                visible: root.listStateResolved && BluetoothService.powered
                Layout.fillWidth: true
                spacing: 4

                // PAIRED header
                Text {
                    visible: BluetoothService.pairedModel.count > 0
                    text: "PAIRED"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini; font.bold: true
                    topPadding: 4; bottomPadding: 2; leftPadding: Theme.listItemPadding
                }

                Repeater {
                    model: BluetoothService.pairedModel
                    DeviceRow {}
                }

                // DISCOVERED header
                Text {
                    visible: BluetoothService.discoveredModel.count > 0
                    text: "DISCOVERED"; color: Theme.fg4
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini; font.bold: true
                    topPadding: 4; bottomPadding: 2; leftPadding: Theme.listItemPadding
                }

                Repeater {
                    model: BluetoothService.discoveredModel
                    DeviceRow { iconColor: Theme.fg4 }
                }
            }

            // Scanning indicator
            Item {
                visible: root.listStateResolved && BluetoothService.powered && !root.deviceListLoading
                    && BluetoothService.scanning && BluetoothService.pairedModel.count === 0 && BluetoothService.discoveredModel.count === 0
                Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
                implicitHeight: scanningRow.implicitHeight
                RowLayout {
                    id: scanningRow; anchors.centerIn: parent; spacing: 6
                    Components.Icon { source: "../icons/bluetooth-on.svg"; color: Theme.fg4
                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            Components.Anim { from: 1; to: 0.3; duration: 800; easing.type: Easing.InOutQuad }
                            Components.Anim { from: 0.3; to: 1; duration: 800; easing.type: Easing.InOutQuad }
                        }
                    }
                    Text { text: "Scanning…"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }

            // Connecting state
            ColumnLayout {
                visible: root.popupState === "connecting"
                Layout.fillWidth: true; spacing: 8; Layout.alignment: Qt.AlignHCenter

                Text { text: "Connecting to " + BluetoothService.connectingName + "…"; color: Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; Layout.alignment: Qt.AlignHCenter }

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter; width: 120; height: 4; radius: 2; color: Theme.bg3
                    Rectangle {
                        height: parent.height; radius: parent.radius; color: Theme.blueBright
                        SequentialAnimation on width {
                            loops: Animation.Infinite
                            Components.Anim { from: 0; to: 120; duration: 1200; easing.type: Easing.InOutQuad }
                            Components.Anim { from: 120; to: 0; duration: 1200; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }

            // Skeleton loading
            ColumnLayout {
                visible: root.deviceListLoading
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: ListModel {
                        ListElement { skelWidth: 110 }
                        ListElement { skelWidth: 140 }
                        ListElement { skelWidth: 95 }
                    }
                    delegate: Item {
                        required property int skelWidth
                        required property int index
                        Layout.fillWidth: true; height: 30

                        RowLayout {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left; anchors.right: parent.right
                            anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: Theme.listItemPadding
                            spacing: 8
                            Rectangle { width: 14; height: 14; radius: 7; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                            Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                            Item { Layout.fillWidth: true }
                            Rectangle { width: 44; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                        }

                        SequentialAnimation on opacity {
                            loops: Animation.Infinite
                            PauseAnimation { duration: index * 120 }
                            Components.Anim { from: 0.4; to: 0.8; duration: 800; easing.type: Easing.InOutQuad }
                            Components.Anim { from: 0.8; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                        }
                    }
                }
            }
        }
    }
}
