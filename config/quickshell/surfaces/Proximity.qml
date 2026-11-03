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

    Ui.Icon {
        Layout.alignment: Qt.AlignHCenter
        name: root.step === "hold" ? "airpods-case" : "airpods"
        size: 72
        color: root.step === "failed" ? Theme.textTertiary : Theme.text
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
