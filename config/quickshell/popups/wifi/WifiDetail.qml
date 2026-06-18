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
        Behavior on color {
            Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
        }
        Behavior on border.color {
            Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
        }

        RowLayout {
            id: statusRow
            anchors.fill: parent; anchors.margins: 10
            spacing: 8

            Rectangle {
                width: 8; height: 8; radius: 4
                color: root.targetIsConnected ? Theme.greenBright : Theme.fg4
                Behavior on color {
                    Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                }
            }

            Text {
                text: root.targetIsConnected ? "Connected" : (root.targetIsKnown ? "Saved Network" : "Not Connected")
                color: root.targetIsConnected ? Theme.greenBright : Theme.fg4
                font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true
                Behavior on color {
                    Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                }
            }

            Item { Layout.fillWidth: true }

            Components.Icon {
                source: root.connectionType === "ethernet" ? "../icons/ethernet.svg" : root.signalIcon(root.targetSignal)
                color: root.targetIsConnected ? Theme.greenBright : Theme.fg4
                iconSize: Theme.iconSize
                Behavior on color {
                    Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                }
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

            Text { visible: root.connectionType === "ethernet"; text: "Connection"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.connectionType === "ethernet"; text: root.connectionLabel || "Ethernet"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { visible: root.connectionType === "wifi"; text: "Security"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.connectionType === "wifi"; text: root.targetSecurity || "Open"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { visible: root.connectionType === "wifi"; text: "Signal"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.connectionType === "wifi"; text: root.targetSignal + "%"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; horizontalAlignment: Text.AlignRight }

            Components.Divider { visible: root.targetIsConnected; Layout.columnSpan: 2 }

            Text { visible: root.targetIsConnected; text: "IP Address"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.targetIsConnected; text: root.detailIp || "\u2026"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { visible: root.targetIsConnected; text: "Gateway"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.targetIsConnected; text: root.detailGateway || "\u2026"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { visible: root.targetIsConnected; text: "DNS"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.targetIsConnected; text: root.detailDns || "\u2026"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { visible: root.targetIsConnected && root.connectionType === "wifi" && root.detailFreq !== ""; text: "Frequency"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.targetIsConnected && root.connectionType === "wifi" && root.detailFreq !== ""; text: root.detailFreq; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { visible: root.targetIsConnected && root.connectionType === "ethernet"; text: "Link Speed"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.targetIsConnected && root.connectionType === "ethernet"; text: root.detailLinkSpeed !== "" ? root.detailLinkSpeed + " Mbps" : "\u2026"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }

            Text { visible: root.targetIsConnected && root.connectionType === "ethernet"; text: "Duplex"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            Text { visible: root.targetIsConnected && root.connectionType === "ethernet"; text: root.detailDuplex || "\u2026"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                Layout.fillWidth: true; elide: Text.ElideRight; horizontalAlignment: Text.AlignRight }
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
            Behavior on color {
                Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
            }
            Components.HoverLayer {
                id: connectArea
                hoverOpacity: 0; pressedOpacity: 0; pressedScale: 0.98
                onClicked: root.connectRequested(root.targetSsid, root.targetSecurity)

                Text { anchors.centerIn: parent; text: "Connect"; color: connectArea.containsMouse ? Theme.bg : Theme.fg
                    Behavior on color {
                        Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                    }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
            }
        }

        // Disconnect button (connected only)
        Rectangle {
            visible: root.targetIsConnected
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: "transparent"
            Components.HoverLayer {
                id: disconnectArea
                color: Theme.bg2; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                disabled: NetworkService.disconnectPending
                onClicked: root.disconnectRequested()

                Text { anchors.centerIn: parent; text: NetworkService.disconnectPending ? "Disconnecting…" : "Disconnect"; color: disconnectArea.containsMouse ? Theme.fg : Theme.fg4
                    Behavior on color {
                        Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                    }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            }
        }

        // Forget button (known networks only)
        Rectangle {
            visible: root.targetIsKnown && root.connectionType === "wifi"
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: "transparent"
            Components.HoverLayer {
                id: forgetArea
                color: Theme.bg2; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                disabled: NetworkService.forgetPending
                onClicked: root.forgetRequested()

                Text { anchors.centerIn: parent; text: NetworkService.forgetPending ? "Forgetting…" : "Forget This Network"; color: forgetArea.containsMouse ? Theme.redBright : Theme.fg4
                    Behavior on color {
                        Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                    }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            }
        }

        // Diagnostics button (connected only)
        Rectangle {
            visible: root.targetIsConnected
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: "transparent"
            Components.HoverLayer {
                id: diagArea
                color: Theme.bg2; idleOpacity: 0.3; hoverOpacity: 0.6; pressedOpacity: 0.9; pressedScale: 0.98
                onClicked: root.diagnosticsRequested()

                Row { anchors.centerIn: parent; spacing: 6
                    Components.Icon { source: "../icons/stethoscope.svg"; color: diagArea.containsMouse ? Theme.blueBright : Theme.fg4; anchors.verticalCenter: parent.verticalCenter
                        Behavior on color {
                            Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                        }
                    }
                    Text { text: "Run Diagnostics"; color: diagArea.containsMouse ? Theme.blueBright : Theme.fg4; anchors.verticalCenter: parent.verticalCenter
                        Behavior on color {
                            Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard }
                        }
                        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
                }
            }
        }
    }
}
