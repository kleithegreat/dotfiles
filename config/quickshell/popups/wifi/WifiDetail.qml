import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

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
    signal forgetRequested()
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
            Behavior on color {
                Components.CAnim {
                    duration: Theme.animHover
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveStandard
                }
            }
            Components.HoverLayer {
                id: detailConnA
                hoverOpacity: 0
                pressedOpacity: 0
                pressedScale: 0.98
                onClicked: root.connectRequested(root.targetSsid, root.targetSecurity)

                Text { anchors.centerIn: parent; text: "Connect"; color: detailConnA.containsMouse ? Theme.bg : Theme.fg
                    Behavior on color {
                        Components.CAnim {
                            duration: Theme.animHover
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
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
                id: detailDcA
                color: Theme.bg2
                hoverOpacity: 0.6
                pressedOpacity: 0.9
                pressedScale: 0.98
                onClicked: root.disconnectRequested()

                Text { anchors.centerIn: parent; text: "Disconnect"; color: detailDcA.containsMouse ? Theme.fg : Theme.fg4
                    Behavior on color {
                        Components.CAnim {
                            duration: Theme.animHover
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            }
        }

        // Forget button (known networks only)
        Rectangle {
            visible: root.targetIsKnown
            Layout.fillWidth: true; height: 32; radius: Theme.btnRadius
            color: "transparent"
            Components.HoverLayer {
                id: forgetA
                color: Theme.bg2
                hoverOpacity: 0.6
                pressedOpacity: 0.9
                pressedScale: 0.98
                onClicked: root.forgetRequested()

                Text { anchors.centerIn: parent; text: "Forget This Network"; color: forgetA.containsMouse ? Theme.redBright : Theme.fg4
                    Behavior on color {
                        Components.CAnim {
                            duration: Theme.animHover
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
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
                id: detailDiagA
                color: Theme.bg2
                idleOpacity: 0.3
                hoverOpacity: 0.6
                pressedOpacity: 0.9
                pressedScale: 0.98
                onClicked: root.diagnosticsRequested()

                Text { anchors.centerIn: parent; text: "󱍸  Run Diagnostics"; color: detailDiagA.containsMouse ? Theme.blueBright : Theme.fg4
                    Behavior on color {
                        Components.CAnim {
                            duration: Theme.animHover
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
            }
        }
    }
}
