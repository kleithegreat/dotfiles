import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Item {
    id: root
    required property var netModel
    required property string connectedSsid
    required property bool isCaptivePortal

    signal connectRequested(string ssid, string security)
    signal detailRequested(string ssid, string security, int signal, bool isActive)
    signal captiveLoginRequested()

    function signalIcon(sig) {
        if (sig > 75) return "../icons/wifi.svg";
        if (sig > 50) return "../icons/wifi-good.svg";
        if (sig > 25) return "../icons/wifi-fair.svg";
        return "../icons/wifi-poor.svg";
    }

    function isEnterprise(sec) { return sec.indexOf("802.1X") >= 0; }

    Components.WheelFlickable {
        anchors.fill: parent
        contentHeight: netCol.implicitHeight; clip: true

        Column {
            id: netCol; width: parent.width; spacing: 2

            // ── Captive portal warning ────────────────────────
            Rectangle {
                visible: root.isCaptivePortal
                width: parent.width
                height: visible ? captiveCol.implicitHeight + 12 : 0
                radius: Theme.btnRadius
                color: Theme.bg2
                border.width: 1; border.color: Theme.yellowBright

                ColumnLayout {
                    id: captiveCol
                    anchors.fill: parent; anchors.margins: 8; spacing: 6

                    RowLayout { spacing: 6
                        Text { text: "\u26a0"; font.pixelSize: Theme.iconSize; color: Theme.yellowBright }
                        Text { text: "Captive Portal Detected"; color: Theme.yellowBright
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                    }
                    Text {
                        text: "This network requires login. Open a browser to authenticate."
                        color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                    Rectangle {
                        width: captiveLoginLabel.implicitWidth + Theme.btnPaddingH * 2
                        height: Theme.btnHeight; radius: Theme.btnRadius
                        color: Theme.yellowBright
                        Components.HoverLayer {
                            id: captiveLoginA
                            hoverOpacity: 0
                            pressedOpacity: 0
                            pressedScale: 0.98
                            onClicked: root.captiveLoginRequested()

                            Text { id: captiveLoginLabel; anchors.centerIn: parent; text: "Open Login Page"
                                color: Theme.bg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; font.bold: true }
                        }
                    }
                }
            }

            Repeater {
                model: root.netModel
                Rectangle {
                    id: netItem; required property string ssid; required property int signal
                    required property string security; required property bool active
                    required property int index
                    width: netCol.width; height: 34; radius: Theme.hoverRadius
                    color: "transparent"

                    Rectangle {
                        anchors.fill: parent; radius: parent.radius; color: Theme.bg2
                        opacity: niRowArea.pressed ? 0.9 : (niRowArea.containsMouse ? 0.6 : 0)
                        Behavior on opacity {
                            Components.Anim {
                                duration: Theme.animHover
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveStandard
                            }
                        }
                    }
                    scale: niRowArea.pressed ? 0.98 : 1.0
                    Behavior on scale {
                        Components.Anim {
                            duration: Theme.animMicro
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Theme.animCurveStandard
                        }
                    }
                    transformOrigin: Item.Center

                    RowLayout {
                        anchors.fill: parent; anchors.leftMargin: Theme.listItemPadding; anchors.rightMargin: 4; spacing: 6

                        // Checkmark for connected, signal-strength icon otherwise
                        Components.Icon {
                            source: netItem.active ? "../icons/circle-check.svg" : root.signalIcon(netItem.signal)
                            color: {
                                if (netItem.active) return Theme.greenBright;
                                if (netItem.signal > 60) return Theme.fg;
                                if (netItem.signal > 30) return Theme.fg3;
                                return Theme.fg4;
                            }
                            Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                        }
                        // SSID
                        Text { text: netItem.ssid; color: netItem.active ? Theme.greenBright : Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            Layout.fillWidth: true; elide: Text.ElideRight }
                        // Enterprise badge
                        Components.Icon { visible: root.isEnterprise(netItem.security); source: "../icons/certificate.svg"; color: Theme.yellowBright }
                        // Lock icon
                        Components.Icon { visible: netItem.security !== "" && !root.isEnterprise(netItem.security); source: "../icons/lock.svg"; color: Theme.fg4 }
                        // Signal %
                        Text { text: netItem.signal + "%"; color: Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                        // info button
                            Rectangle {
                                width: 24; height: 24; radius: 12
                                color: "transparent"
                                Components.HoverLayer {
                                    id: infoA
                                    color: Theme.bg2
                                    hoverOpacity: 0.7
                                    pressedOpacity: 0.9
                                    onClicked: root.detailRequested(netItem.ssid, netItem.security, netItem.signal, netItem.active)

                                    Components.Icon { anchors.centerIn: parent; source: "../icons/info-circle.svg"; color: infoA.containsMouse ? Theme.blueBright : Theme.fg4
                                        Behavior on color {
                                            Components.CAnim {
                                                duration: Theme.animHover
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Theme.animCurveStandard
                                            }
                                        }
                                    }
                                }
                            }
                    }

                    // Row click: connected -> detail, otherwise -> connect
                    Components.HoverLayer {
                        id: niRowArea; anchors.left: parent.left; anchors.top: parent.top
                        anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.rightMargin: 30
                        hoverOpacity: 0
                        pressedOpacity: 0
                        pressedScale: 1.0
                        onClicked: {
                            if (netItem.active)
                                root.detailRequested(netItem.ssid, netItem.security, netItem.signal, true);
                            else
                                root.connectRequested(netItem.ssid, netItem.security);
                        }
                    }
                }
            }
        }
    }

    // ── Skeleton loading rows ─────────────────────
    Column {
        visible: root.netModel.count === 0
        anchors.fill: parent; anchors.topMargin: 4
        spacing: 0

        Repeater {
            model: ListModel {
                ListElement { skelWidth: 120 }
                ListElement { skelWidth: 90 }
                ListElement { skelWidth: 150 }
                ListElement { skelWidth: 105 }
            }
            delegate: Item {
                required property int skelWidth
                required property int index
                width: parent.width; height: 36
                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: 6; anchors.rightMargin: 6
                    spacing: 8

                    Rectangle { width: skelWidth; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                    Item { Layout.fillWidth: true }
                    Rectangle { width: 10; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
                    Rectangle { width: 28; height: 10; radius: 5; color: Theme.bg3; Layout.alignment: Qt.AlignVCenter }
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
}
