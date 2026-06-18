import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

ColumnLayout {
    id: root
    required property string targetSsid
    required property string connectError

    property bool passwordVisible: false
    property bool submitAttempted: false
    readonly property string trimmedIdentity: eapIdentity.text.trim()
    readonly property string trimmedPassword: eapPassword.text.trim()
    readonly property bool canSubmit: root.trimmedIdentity !== "" && root.trimmedPassword !== ""
    readonly property string identityErrorText: root.submitAttempted && root.trimmedIdentity === "" ? "Identity required." : ""
    readonly property string passwordErrorText: {
        if (root.connectError !== "")
            return root.connectError;
        if (root.submitAttempted && root.trimmedPassword === "")
            return "Password required.";
        return "";
    }

    signal enterpriseSubmitted(string identity, string password)
    signal backRequested()

    onVisibleChanged: {
        if (visible) {
            eapIdentity.text = "";
            eapPassword.text = "";
            root.passwordVisible = false;
            root.submitAttempted = false;
            eapIdentity.forceActiveFocus();
        }
    }

    function submit() {
        if (!root.canSubmit) {
            root.submitAttempted = true;
            if (root.trimmedIdentity === "")
                eapIdentity.forceActiveFocus();
            else
                eapPassword.forceActiveFocus();
            return;
        }

        root.submitAttempted = false;
        root.enterpriseSubmitted(root.trimmedIdentity, root.trimmedPassword);
    }

    spacing: 8

    Text { text: "Network: " + root.targetSsid; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
    Text { text: "802.1X \u00b7 PEAP / MSCHAPv2"; color: Theme.fg4
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini }

    Rectangle {
        Layout.fillWidth: true; height: 36; radius: Theme.btnRadius; color: Theme.bg2
        border.width: 1
        border.color: root.identityErrorText !== ""
            ? Theme.redBright
            : (eapIdentity.activeFocus ? Theme.blueBright : Theme.bg3)
        Behavior on border.color {
            Components.CAnim {
                duration: Theme.animHover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }

        Rectangle {
            visible: eapIdentity.text !== ""
            width: 22
            height: 22
            radius: Theme.hoverRadius
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            color: identityClearArea.containsMouse ? Theme.bg3 : "transparent"
            border.width: 1
            border.color: identityClearArea.containsMouse ? Theme.bg3 : "transparent"
            Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
            Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

            Components.Icon {
                anchors.centerIn: parent
                source: "../../icons/close.svg"
                color: Theme.fg4
                iconSize: Theme.fontSizeSmall
            }

            Components.HoverLayer {
                id: identityClearArea
                anchors.fill: parent
                hoverOpacity: 0
                pressedOpacity: 0
                pressedScale: 1.0
                onClicked: {
                    eapIdentity.text = "";
                    root.submitAttempted = false;
                    eapIdentity.forceActiveFocus();
                }
            }
        }

        TextInput {
            id: eapIdentity
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 36
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; clip: true
            onTextEdited: root.submitAttempted = false
            Keys.onReturnPressed: {
                if (root.trimmedIdentity === "") {
                    root.submitAttempted = true;
                    return;
                }

                eapPassword.forceActiveFocus();
            }
            Keys.onEscapePressed: root.backRequested()
        }
        Text { visible: !eapIdentity.text; text: "Username / Identity"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
    }

    Text {
        visible: root.identityErrorText !== ""
        text: root.identityErrorText
        color: Theme.redBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMini
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    Rectangle {
        Layout.fillWidth: true; height: 36; radius: Theme.btnRadius; color: Theme.bg2
        border.width: 1
        border.color: root.passwordErrorText !== ""
            ? Theme.redBright
            : (eapPassword.activeFocus ? Theme.blueBright : Theme.bg3)
        Behavior on border.color {
            Components.CAnim {
                duration: Theme.animHover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }

        Row {
            id: passwordActions
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                width: passwordRevealLabel.implicitWidth + 10
                height: 22
                radius: Theme.hoverRadius
                color: passwordRevealArea.containsMouse ? Theme.bg3 : "transparent"
                border.width: 1
                border.color: passwordRevealArea.containsMouse ? Theme.bg3 : "transparent"
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Text {
                    id: passwordRevealLabel
                    anchors.centerIn: parent
                    text: root.passwordVisible ? "Hide" : "Show"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMini
                }

                Components.HoverLayer {
                    id: passwordRevealArea
                    anchors.fill: parent
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: {
                        root.passwordVisible = !root.passwordVisible;
                        eapPassword.forceActiveFocus();
                    }
                }
            }

            Rectangle {
                visible: eapPassword.text !== ""
                width: 22
                height: 22
                radius: Theme.hoverRadius
                color: passwordClearArea.containsMouse ? Theme.bg3 : "transparent"
                border.width: 1
                border.color: passwordClearArea.containsMouse ? Theme.bg3 : "transparent"
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Components.Icon {
                    anchors.centerIn: parent
                    source: "../../icons/close.svg"
                    color: Theme.fg4
                    iconSize: Theme.fontSizeSmall
                }

                Components.HoverLayer {
                    id: passwordClearArea
                    anchors.fill: parent
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: {
                        eapPassword.text = "";
                        root.submitAttempted = false;
                        eapPassword.forceActiveFocus();
                    }
                }
            }
        }

        TextInput {
            id: eapPassword
            anchors.left: parent.left
            anchors.right: passwordActions.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            color: Theme.fg; selectionColor: Theme.blueBright; selectedTextColor: Theme.bg
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
            echoMode: root.passwordVisible ? TextInput.Normal : TextInput.Password
            clip: true
            onTextEdited: root.submitAttempted = false
            Keys.onReturnPressed: root.submit()
            Keys.onEscapePressed: root.backRequested()
        }
        Text { visible: !eapPassword.text; text: "Password"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall }
    }

    Text {
        visible: root.passwordErrorText !== ""
        text: root.passwordErrorText
        color: Theme.redBright
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMini
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
    }

    Rectangle {
        Layout.fillWidth: true; height: 30; radius: Theme.btnRadius
        color: root.canSubmit ? (connEapA.containsMouse ? Theme.blueBright : Theme.bg3) : Theme.bg2
        opacity: root.canSubmit ? 1 : 0.6
        Behavior on color {
            Components.CAnim {
                duration: Theme.animHover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }
        Components.HoverLayer {
            id: connEapA
            disabled: !root.canSubmit
            hoverOpacity: 0
            pressedOpacity: 0
            pressedScale: 0.98
            onClicked: root.submit()

            Text { anchors.centerIn: parent; text: "Sign In"; color: root.canSubmit ? (connEapA.containsMouse ? Theme.bg : Theme.fg) : Theme.fg4
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
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMicro; Layout.fillWidth: true }
}
