import QtQuick
import Quickshell.Wayland
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

// The card an open AirPods case raises, as on an iPhone: its charge when the
// pair is known here, setup when it is not ([[airpods]]).
Card {
    id: root

    readonly property string live: Sys.AirPods.card
    // Kept through the exit so the card does not go blank while it leaves.
    property string step: ""

    onLiveChanged: {
        if (live !== "")
            step = live;
    }

    shown: live !== ""
    WlrLayershell.namespace: "quickshell:proximity"

    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.s2

        Ui.Label {
            Layout.fillWidth: true
            text: Sys.AirPods.link?.name ?? Sys.AirPods.model
            role: "title"
            elide: Text.ElideRight
        }

        Ui.IconButton {
            name: "close"
            onClicked: Sys.AirPods.dismiss()
        }
    }

    // The case with its pods hovering over it. They settle in as the card
    // rises, then drift, out of step with each other.
    Item {
        id: scene

        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 132
        implicitHeight: 112
        opacity: root.step === "failed" ? 0.45 : 1
        scale: root.shown ? 1 : 0.8

        Ui.Reveal on scale {
            shownValue: 1
        }
        Behavior on opacity {
            Ui.Anim {}
        }

        Repeater {
            model: [
                { icon: "pod-left", x: 26, phase: 0 },
                { icon: "pod-right", x: 70, phase: 700 }
            ]

            Ui.Icon {
                id: pod

                required property var modelData
                property real drift: 0

                x: pod.modelData.x
                y: 4 + pod.drift
                name: pod.modelData.icon
                size: 36
                color: Theme.text

                SequentialAnimation on drift {
                    running: root.shown
                    loops: Animation.Infinite

                    PauseAnimation {
                        duration: pod.modelData.phase
                    }
                    NumberAnimation {
                        from: 0
                        to: -5
                        duration: 1400
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        from: -5
                        to: 0
                        duration: 1400
                        easing.type: Easing.InOutSine
                    }
                }
            }
        }

        Ui.Icon {
            id: caseIcon

            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            name: "airpods-case"
            size: 64
            color: Theme.text

            // The status light: white and flashing while the button is held.
            Rectangle {
                x: parent.width / 2 - width / 2
                y: parent.height * 0.62
                width: 5
                height: 5
                radius: 2.5
                color: "white"
                visible: root.step === "hold"

                SequentialAnimation on opacity {
                    running: root.step === "hold"
                    loops: Animation.Infinite

                    NumberAnimation {
                        to: 0.15
                        duration: 450
                    }
                    NumberAnimation {
                        to: 1
                        duration: 450
                    }
                }
            }
        }

        Ui.Ring {
            anchors.centerIn: caseIcon
            implicitWidth: 92
            implicitHeight: 92
            thickness: 3
            busy: true
            track: "transparent"
            visible: root.step === "connecting"
        }
    }

    Ui.PodBattery {
        Layout.fillWidth: true
        visible: root.step === "done" || (root.step === "status" && Sys.AirPods.battery !== null)
        battery: Sys.AirPods.battery
    }

    Ui.Label {
        Layout.fillWidth: true
        visible: text !== ""
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        role: "callout"
        text: {
            switch (root.step) {
            case "status":
                return Sys.AirPods.connected ? "" : "Not connected";
            case "hold":
                return "Press and hold the setup button on the back of the case until the status light flashes white.";
            case "connecting":
                return "Connecting…";
            case "failed":
                return "Couldn't connect. Keep the case open and close to this computer, then try again.";
            }
            return "";
        }
    }

    Ui.Button {
        Layout.fillWidth: true
        variant: "filled"
        visible: text !== ""
        text: {
            switch (root.step) {
            case "connect":
                return "Connect";
            case "status":
                return Sys.AirPods.connected ? "" : "Connect";
            case "done":
                return "Done";
            case "failed":
                return "Try Again";
            }
            return "";
        }
        onClicked: root.step === "done" ? Sys.AirPods.dismiss() : Sys.AirPods.connectCase()
    }
}
