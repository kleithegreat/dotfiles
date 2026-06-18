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
    readonly property string trimmedPassword: pskInput.text.trim()
    readonly property bool canSubmit: root.trimmedPassword !== ""
    readonly property string passwordErrorText: {
        if (root.connectError !== "")
            return root.connectError;
        if (root.submitAttempted && !root.canSubmit)
            return "Password required.";
        return "";
    }

    signal passwordSubmitted(string password)
    signal backRequested()

    onVisibleChanged: {
        if (visible) {
            pskInput.text = "";
            root.passwordVisible = false;
            root.submitAttempted = false;
            pskInput.forceActiveFocus();
        }
    }

    function submit() {
        if (!root.canSubmit) {
            root.submitAttempted = true;
            pskInput.forceActiveFocus();
            return;
        }

        root.submitAttempted = false;
        root.passwordSubmitted(root.trimmedPassword);
    }

    spacing: 8

    Text { text: "Network: " + root.targetSsid; color: Theme.fg
        font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }

    Rectangle {
        Layout.fillWidth: true; height: 36; radius: Theme.btnRadius; color: Theme.bg2
        border.width: 1
        border.color: root.passwordErrorText !== ""
            ? Theme.redBright
            : (pskInput.activeFocus ? Theme.blueBright : Theme.bg3)
        Behavior on border.color {
            Components.CAnim {
                duration: Theme.animHover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }

        Row {
            id: pskActions
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            Rectangle {
                width: revealLabel.implicitWidth + 10
                height: 22
                radius: Theme.hoverRadius
                color: revealArea.containsMouse ? Theme.bg3 : "transparent"
                border.width: 1
                border.color: revealArea.containsMouse ? Theme.bg3 : "transparent"
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Text {
                    id: revealLabel
                    anchors.centerIn: parent
                    text: root.passwordVisible ? "Hide" : "Show"
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMini
                }

                Components.HoverLayer {
                    id: revealArea
                    anchors.fill: parent
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: {
                        root.passwordVisible = !root.passwordVisible;
                        pskInput.forceActiveFocus();
                    }
                }
            }

            Rectangle {
                visible: pskInput.text !== ""
                width: 22
                height: 22
                radius: Theme.hoverRadius
                color: clearArea.containsMouse ? Theme.bg3 : "transparent"
                border.width: 1
                border.color: clearArea.containsMouse ? Theme.bg3 : "transparent"
                Behavior on color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }
                Behavior on border.color { Components.CAnim { duration: Theme.animHover; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveStandard } }

                Components.Icon {
                    anchors.centerIn: parent
                    source: "../../icons/close.svg"
                    color: Theme.fg4
                    iconSize: Theme.fontSizeSmall
                }

                Components.HoverLayer {
                    id: clearArea
                    anchors.fill: parent
                    hoverOpacity: 0
                    pressedOpacity: 0
                    pressedScale: 1.0
                    onClicked: {
                        pskInput.text = "";
                        root.submitAttempted = false;
                        pskInput.forceActiveFocus();
                    }
                }
            }
        }

        TextInput {
            id: pskInput
            anchors.left: parent.left
            anchors.right: pskActions.left
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
        Text { visible: !pskInput.text; text: "Password"; color: Theme.fg4; anchors.left: parent.left; anchors.leftMargin: 8; anchors.verticalCenter: parent.verticalCenter
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
        color: root.canSubmit ? (connPskA.containsMouse ? Theme.blueBright : Theme.bg3) : Theme.bg2
        opacity: root.canSubmit ? 1 : 0.6
        Behavior on color {
            Components.CAnim {
                duration: Theme.animHover
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveStandard
            }
        }
        Components.HoverLayer {
            id: connPskA
            disabled: !root.canSubmit
            hoverOpacity: 0
            pressedOpacity: 0
            pressedScale: 0.98
            onClicked: root.submit()

            Text { anchors.centerIn: parent; text: "Connect"; color: root.canSubmit ? (connPskA.containsMouse ? Theme.bg : Theme.fg) : Theme.fg4
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
}
