import qs
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property string targetSsid
    required property string targetSecurity
    required property int targetSignal
    required property bool targetIsConnected
    required property bool targetIsKnown
    required property string detailIp
    required property string detailGateway
    required property string detailDns
    required property string detailFreq
    required property string connectError

    signal connectRequested(string ssid, string security)
    signal disconnectRequested()
    signal forgetRequested(string ssid)
    signal diagnosticsRequested()

    function signalIcon(sig) {
        if (sig > 75) return "󰤨";
        if (sig > 50) return "󰤥";
        if (sig > 25) return "󰤢";
        return "󰤟";
    }

    spacing: 10

    // Status row
    RowLayout {
        Layout.fillWidth: true; spacing: 8
        Text { text: root.signalIcon(root.targetSignal); color: root.targetIsConnected ? Theme.greenBright : Theme.fg
            font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize + 4 }
        ColumnLayout {
            spacing: 2; Layout.fillWidth: true
            Text { text: root.targetIsConnected ? "Connected" : (root.targetIsKnown ? "Known Network" : "Not Connected")
                color: root.targetIsConnected ? Theme.greenBright : Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            Text { text: root.targetSecurity || "Open"; color: Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
        }
        Text { text: root.targetSignal + "%"; color: Theme.fg4
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
    }

    // Detail fields (connected only)
    Rectangle {
        visible: root.targetIsConnected
            Layout.fillWidth: true; implicitHeight: detailGrid.implicitHeight + 16; radius: Theme.btnRadius; color: Theme.bg2

        GridLayout {
            id: detailGrid; anchors.fill: parent; anchors.margins: 8
            columns: 2; columnSpacing: 12; rowSpacing: 6

            Text { text: "IP Address"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
            Text { text: root.detailIp || "\u2026"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { text: "Gateway"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
            Text { text: root.detailGateway || "\u2026"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { text: "DNS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
            Text { text: root.detailDns || "\u2026"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { visible: root.detailFreq !== ""; text: "Frequency"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
            Text { visible: root.detailFreq !== ""; text: root.detailFreq; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }
        }
    }

    // Action buttons
    ColumnLayout {
        Layout.fillWidth: true; spacing: 6; Layout.topMargin: -4

        // Connect button (not connected)
        Rectangle {
            visible: !root.targetIsConnected
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: detailConnA.containsMouse ? Theme.blueBright : Theme.bg3
            Behavior on color { ColorAnimation { duration: Theme.animHover } }
            scale: detailConnA.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
            transformOrigin: Item.Center
            Text { anchors.centerIn: parent; text: "Connect"; color: detailConnA.containsMouse ? Theme.bg : Theme.fg
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            MouseArea { id: detailConnA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: root.connectRequested(root.targetSsid, root.targetSecurity) }
        }

        // Disconnect button (connected only)
        Rectangle {
            visible: root.targetIsConnected
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: "transparent"
            Rectangle {
                anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                opacity: detailDcA.pressed ? 0.9 : (detailDcA.containsMouse ? 0.6 : 0)
                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
            }
            scale: detailDcA.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
            transformOrigin: Item.Center
            Text { anchors.centerIn: parent; text: "Disconnect"; color: detailDcA.containsMouse ? Theme.fg : Theme.fg4
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            MouseArea { id: detailDcA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: root.disconnectRequested() }
        }

        // Forget button (known networks only)
        Rectangle {
            visible: root.targetIsKnown
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: "transparent"
            Rectangle {
                anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                opacity: forgetA.pressed ? 0.9 : (forgetA.containsMouse ? 0.6 : 0)
                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
            }
            scale: forgetA.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
            transformOrigin: Item.Center
            Text { anchors.centerIn: parent; text: "Forget This Network"; color: forgetA.containsMouse ? Theme.redBright : Theme.fg4
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            MouseArea { id: forgetA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: root.forgetRequested(root.targetSsid) }
        }

        // Diagnostics button (connected only)
        Rectangle {
            visible: root.targetIsConnected
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: "transparent"
            Rectangle {
                anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                opacity: detailDiagA.pressed ? 0.9 : (detailDiagA.containsMouse ? 0.6 : 0.3)
                Behavior on opacity { NumberAnimation { duration: Theme.animHover; easing.type: Easing.OutCubic } }
            }
            scale: detailDiagA.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: Theme.animMicro; easing.type: Easing.OutCubic } }
            transformOrigin: Item.Center
            Text { anchors.centerIn: parent; text: "󱍸  Run Diagnostics"; color: detailDiagA.containsMouse ? Theme.blueBright : Theme.fg4
                Behavior on color { ColorAnimation { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            MouseArea { id: detailDiagA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                onClicked: root.diagnosticsRequested() }
        }
    }
}
