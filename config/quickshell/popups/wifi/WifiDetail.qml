import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

ColumnLayout {
    id: root
    required property string connectionType
    required property string connectionLabel
    required property string targetSsid
    required property string targetSecurity
    required property int targetSignal
    required property bool targetIsConnected
    required property bool targetIsKnown
    required property string detailIp
    required property string detailGateway
    required property string detailDns
    required property string detailFreq
    required property string detailLinkSpeed
    required property string detailDuplex
    required property string connectError

    signal connectRequested(string ssid, string security)
    signal disconnectRequested()
    signal forgetRequested()
    signal diagnosticsRequested()

    function signalIcon(sig) {
        if (sig > 75) return "../icons/wifi.svg";
        if (sig > 50) return "../icons/wifi-good.svg";
        if (sig > 25) return "../icons/wifi-fair.svg";
        return "../icons/wifi-poor.svg";
    }

    component InfoLabel: Text {
        color: Theme.fg4
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
    }

    component InfoValue: Text {
        color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
        Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight
    }

    // Ghost action button: transparent until hovered, with pending-state label.
    component DetailActionButton: Rectangle {
        id: actionBtn

        required property string text
        property string pendingText: ""
        property bool pending: false
        property color hoverColor: Theme.fg

        signal clicked()

        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
        color: "transparent"
        Components.HoverLayer {
            id: actionArea
            disabled: actionBtn.pending
            onClicked: actionBtn.clicked()

            Text { anchors.centerIn: parent
                text: actionBtn.pending && actionBtn.pendingText !== "" ? actionBtn.pendingText : actionBtn.text
                color: actionArea.containsMouse ? actionBtn.hoverColor : Theme.fg4
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
        }
    }

    spacing: 12

    // Status badge
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: statusRow.implicitHeight + 20
        radius: Theme.hoverRadius
        color: root.targetIsConnected
            ? Qt.rgba(Theme.greenBright.r, Theme.greenBright.g, Theme.greenBright.b, 0.08)
            : Theme.bg2
        border.width: root.targetIsConnected ? 1 : 0
        border.color: root.targetIsConnected
            ? Qt.rgba(Theme.greenBright.r, Theme.greenBright.g, Theme.greenBright.b, 0.2)
            : "transparent"
        Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
        Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

        RowLayout {
            id: statusRow
            anchors.fill: parent; anchors.margins: 10
            spacing: 8

            Rectangle {
                width: 8; height: 8; radius: 4
                color: root.targetIsConnected ? Theme.greenBright : Theme.fg4
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
            }

            Text {
                text: root.targetIsConnected ? "Connected" : (root.targetIsKnown ? "Saved Network" : "Not Connected")
                color: root.targetIsConnected ? Theme.greenBright : Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
            }

            Item { Layout.fillWidth: true }

            Components.Icon {
                source: root.connectionType === "ethernet" ? "../icons/ethernet.svg" : root.signalIcon(root.targetSignal)
                color: root.targetIsConnected ? Theme.greenBright : Theme.fg4
                iconSize: Theme.iconSize
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
            }
        }
    }

    // Network info card
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: infoGrid.implicitHeight + 20
        radius: Theme.hoverRadius
        color: Theme.bg2

        GridLayout {
            id: infoGrid
            anchors.fill: parent; anchors.margins: 10
            columns: 2; columnSpacing: 12; rowSpacing: 8

            InfoLabel { visible: root.connectionType === "ethernet"; text: "Connection" }
            InfoValue { visible: root.connectionType === "ethernet"; text: root.connectionLabel || "Ethernet" }

            InfoLabel { visible: root.connectionType === "wifi"; text: "Security" }
            InfoValue { visible: root.connectionType === "wifi"; text: root.targetSecurity || "Open" }

            InfoLabel { visible: root.connectionType === "wifi"; text: "Signal" }
            InfoValue { visible: root.connectionType === "wifi"; text: root.targetSignal + "%" }

            Components.Divider { visible: root.targetIsConnected; Layout.columnSpan: 2 }

            InfoLabel { visible: root.targetIsConnected; text: "IP Address" }
            InfoValue { visible: root.targetIsConnected; text: root.detailIp || "\u2026" }

            InfoLabel { visible: root.targetIsConnected; text: "Gateway" }
            InfoValue { visible: root.targetIsConnected; text: root.detailGateway || "\u2026" }

            InfoLabel { visible: root.targetIsConnected; text: "DNS" }
            InfoValue { visible: root.targetIsConnected; text: root.detailDns || "\u2026" }

            InfoLabel { visible: root.targetIsConnected && root.connectionType === "wifi" && root.detailFreq !== ""; text: "Frequency" }
            InfoValue { visible: root.targetIsConnected && root.connectionType === "wifi" && root.detailFreq !== ""; text: root.detailFreq }

            InfoLabel { visible: root.targetIsConnected && root.connectionType === "ethernet"; text: "Link Speed" }
            InfoValue { visible: root.targetIsConnected && root.connectionType === "ethernet"; text: root.detailLinkSpeed !== "" ? root.detailLinkSpeed + " Mbps" : "\u2026" }

            InfoLabel { visible: root.targetIsConnected && root.connectionType === "ethernet"; text: "Duplex" }
            InfoValue { visible: root.targetIsConnected && root.connectionType === "ethernet"; text: root.detailDuplex || "\u2026" }
        }
    }

    // Error message
    Text {
        visible: root.connectError !== ""
        Layout.fillWidth: true
        text: root.connectError
        color: Theme.redBright
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
        wrapMode: Text.WordWrap
    }

    // Actions
    Components.Divider {}

    ColumnLayout {
        Layout.fillWidth: true; spacing: 6

        // Connect button (not connected)
        Rectangle {
            visible: !root.targetIsConnected && root.connectionType === "wifi"
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: connectArea.containsMouse ? Theme.blueBright : Theme.bg3
            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
            Components.HoverLayer {
                id: connectArea
                hoverOpacity: 0; pressedOpacity: 0
                onClicked: root.connectRequested(root.targetSsid, root.targetSecurity)

                Text { anchors.centerIn: parent; text: "Connect"; color: connectArea.containsMouse ? Theme.bg : Theme.fg
                    Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            }
        }

        DetailActionButton {
            visible: root.targetIsConnected
            text: "Disconnect"
            pendingText: "Disconnecting\u2026"
            pending: NetworkService.disconnectPending
            onClicked: root.disconnectRequested()
        }

        DetailActionButton {
            visible: root.targetIsKnown && root.connectionType === "wifi"
            text: "Forget This Network"
            pendingText: "Forgetting\u2026"
            pending: NetworkService.forgetPending
            hoverColor: Theme.redBright
            onClicked: root.forgetRequested()
        }

        // Diagnostics button (connected only)
        Rectangle {
            visible: root.targetIsConnected
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: "transparent"
            Components.HoverLayer {
                id: diagArea
                idleOpacity: 0.3
                onClicked: root.diagnosticsRequested()

                Row { anchors.centerIn: parent; spacing: 6
                    Components.Icon { source: "../icons/stethoscope.svg"; color: diagArea.containsMouse ? Theme.blueBright : Theme.fg4; anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                    }
                    Text { text: "Run Diagnostics"; color: diagArea.containsMouse ? Theme.blueBright : Theme.fg4; anchors.verticalCenter: parent.verticalCenter
                        Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }
        }
    }
}
