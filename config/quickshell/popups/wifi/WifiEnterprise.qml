import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

ColumnLayout {
    id: root
    required property string targetSsid
    required property string connectError

    signal enterpriseSubmitted(string identity, string password)
    signal backRequested()

    onVisibleChanged: {
        if (visible) { eapIdentity.text = ""; eapPassword.text = ""; eapIdentity.forceActiveFocus(); }
    }

    spacing: 8

    Text { text: "Network: " + root.targetSsid; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
    Text { text: "802.1X \u00b7 PEAP / MSCHAPv2"; color: Theme.fg4
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }

    Rectangle {
        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
        border.width: 1; border.color: eapIdentity.activeFocus ? Theme.blueBright : Theme.bg3
        Behavior on border.color {
            Components.CAnim {
                duration: Theme.animHover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }
        TextInput {
            id: eapIdentity; anchors.fill: parent; anchors.margins: 8
            color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; clip: true
            Keys.onReturnPressed: eapPassword.forceActiveFocus()
            Keys.onEscapePressed: root.backRequested()
        }
        Text { visible: !eapIdentity.text; text: "Username / Identity"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
    }

    Rectangle {
        Layout.fillWidth: true; height: 32; radius: Theme.btnRadius; color: Theme.bg2
        border.width: 1; border.color: eapPassword.activeFocus ? Theme.blueBright : Theme.bg3
        Behavior on border.color {
            Components.CAnim {
                duration: Theme.animHover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }
        TextInput {
            id: eapPassword; anchors.fill: parent; anchors.margins: 8
            color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            echoMode: TextInput.Password; clip: true
            Keys.onReturnPressed: root.enterpriseSubmitted(eapIdentity.text, text)
            Keys.onEscapePressed: root.backRequested()
        }
        Text { visible: !eapPassword.text; text: "Password"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
    }

    Rectangle {
        Layout.fillWidth: true; height: 30; radius: Theme.btnRadius
        color: connEapA.containsMouse ? Theme.blueBright : Theme.bg3
        Behavior on color {
            Components.CAnim {
                duration: Theme.animHover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }
        Components.HoverLayer {
            id: connEapA
            hoverOpacity: 0
            pressedOpacity: 0
            pressedScale: 0.98
            onClicked: root.enterpriseSubmitted(eapIdentity.text, eapPassword.text)

            Text { anchors.centerIn: parent; text: "Sign In"; color: connEapA.containsMouse ? Theme.bg : Theme.fg
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

    Text { text: "Only PEAP/MSCHAPv2 is supported."; color: Theme.fg4; wrapMode: Text.WordWrap
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 2; Layout.fillWidth: true }
}
