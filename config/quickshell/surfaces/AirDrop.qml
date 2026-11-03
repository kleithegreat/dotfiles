import QtQuick
import Quickshell.Wayland
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

// AirDrop's card ([[airdrop]]): an offer coming in, what it delivered, or the
// receivers a share can go to.
Card {
    id: root

    readonly property string live: Sys.AirDrop.request ? Sys.AirDrop.request.accepted ? "receiving" : "offer" : Sys.AirDrop.delivered ? "delivered" : Sys.AirDrop.share ? "share" : ""
    // Kept through the exit so the card does not go blank while it leaves.
    property string step: ""

    onLiveChanged: {
        if (live !== "")
            step = live;
    }

    shown: live !== ""
    WlrLayershell.namespace: "quickshell:airdrop"

    function describe(files, urls) {
        if (urls.length > 0)
            return urls.length === 1 ? "a link" : urls.length + " links";
        return files.length === 1 ? "“" + files[0] + "”" : files.length + " items";
    }

    readonly property var ask: Sys.AirDrop.request
    readonly property var gift: Sys.AirDrop.delivered
    readonly property var share: Sys.AirDrop.share

    RowLayout {
        Layout.fillWidth: true
        spacing: Metrics.s2

        Ui.Icon {
            name: "airdrop"
            color: Theme.accent
        }

        Ui.Label {
            Layout.fillWidth: true
            text: "AirDrop"
            role: "title"
        }

        Ui.IconButton {
            visible: root.step === "share" || root.step === "delivered"
            name: "close"
            onClicked: root.step === "share" ? Sys.AirDrop.cancel() : Sys.AirDrop.dismissDelivered()
        }
    }

    Ui.Label {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        role: "body"
        text: {
            switch (root.step) {
            case "offer":
                return root.ask ? root.ask.sender + " would like to share " + root.describe(root.ask.files, root.ask.urls) + "." : "";
            case "receiving":
                return root.ask ? "Receiving from " + root.ask.sender + "…" : "";
            case "delivered":
                return root.gift ? root.gift.sender + " shared " + root.describe(root.gift.paths.map(path => path.split("/").pop()), root.gift.urls) + "." : "";
            case "share":
                return root.share ? "Share " + root.describe(root.share.items, []) + " with" : "";
            }
            return "";
        }
    }

    // A link is shown, never opened unasked.
    Ui.Label {
        Layout.fillWidth: true
        visible: root.step === "delivered" && (root.gift?.urls.length ?? 0) > 0
        text: root.gift?.urls[0] ?? ""
        role: "callout"
        elide: Text.ElideMiddle
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.step === "share"
        spacing: Metrics.s1

        Repeater {
            model: root.share?.receivers ?? []

            Ui.ListRow {
                id: receiver

                required property var modelData
                readonly property var sending: root.share?.sending ?? null
                readonly property bool target: sending !== null && sending.to === receiver.modelData.name

                Layout.fillWidth: true
                icon: "airdrop"
                title: receiver.modelData.name
                subtitle: {
                    if (!receiver.target)
                        return "";
                    switch (receiver.sending.state) {
                    case "asking":
                        return "Waiting…";
                    case "sending":
                        return receiver.sending.total > 0 ? "Sending · " + Math.round(100 * receiver.sending.sent / receiver.sending.total) + "%" : "Sending…";
                    case "sent":
                        return "Sent";
                    case "declined":
                        return "Declined";
                    }
                    return receiver.sending.error || "Failed";
                }
                chevron: receiver.sending === null || ["sent", "declined", "failed"].indexOf(receiver.sending.state) >= 0
                onClicked: {
                    if (receiver.chevron)
                        Sys.AirDrop.send(receiver.modelData.id);
                }
            }
        }

        Ui.Label {
            Layout.fillWidth: true
            visible: (root.share?.receivers.length ?? 0) === 0
            wrapMode: Text.WordWrap
            role: "callout"
            text: Sys.AirDrop.busy ? "Starting AirDrop…" : "Looking for iPhones nearby. They need to be unlocked, with AirDrop set to Everyone for 10 Minutes."
        }
    }

    Ui.Label {
        Layout.fillWidth: true
        visible: Sys.AirDrop.pausesWifi && (root.step === "share" || root.step === "offer")
        wrapMode: Text.WordWrap
        role: "caption"
        text: "Wi-Fi is paused while AirDrop is on."
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.step !== "receiving"
        spacing: Metrics.s2

        Ui.Button {
            Layout.fillWidth: true
            text: root.step === "offer" ? "Decline" : root.step === "share" && root.share?.sending?.state !== "sent" ? "Cancel" : "Done"
            onClicked: {
                if (root.step === "offer")
                    Sys.AirDrop.answer(root.ask.id, false);
                else if (root.step === "share")
                    Sys.AirDrop.cancel();
                else
                    Sys.AirDrop.dismissDelivered();
            }
        }

        Ui.Button {
            Layout.fillWidth: true
            variant: "filled"
            visible: root.step !== "share"
            text: root.step === "offer" ? "Accept" : (root.gift?.urls.length ?? 0) > 0 ? "Open" : "Show in Files"
            onClicked: {
                if (root.step === "offer")
                    Sys.AirDrop.answer(root.ask.id, true);
                else if ((root.gift?.urls.length ?? 0) > 0)
                    Sys.AirDrop.openDelivered();
                else
                    Sys.AirDrop.showDelivered();
            }
        }
    }
}
