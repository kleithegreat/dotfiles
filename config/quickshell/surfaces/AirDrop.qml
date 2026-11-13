import QtQuick
import Quickshell.Wayland
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

// AirDrop's card ([[airdrop]]): an offer coming in, what it delivered, or the
// share sheet a share goes out from.
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

    function initials(name) {
        return name.split(/[\s’']+/).filter(word => word.length > 0 && word !== "s").slice(0, 2).map(word => word[0].toUpperCase()).join("");
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

    // ── Incoming ────────────────────────────────────────────────────────

    Ui.Thumbnail {
        Layout.fillWidth: true
        Layout.preferredHeight: 168
        visible: (root.step === "offer" || root.step === "receiving") && (root.ask?.icon ?? null) !== null
        source: root.ask?.icon ? "file://" + root.ask.icon : ""
    }

    Ui.Label {
        Layout.fillWidth: true
        visible: root.step !== "share"
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

    // ── Outgoing: what is shared, then who can take it ──────────────────

    RowLayout {
        Layout.fillWidth: true
        visible: root.step === "share"
        spacing: Metrics.s3

        Ui.Thumbnail {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            source: root.share?.preview ? "file://" + root.share.preview : ""
            fallback: root.share?.kind === "text" ? "typography" : root.share?.kind === "links" ? "world" : "photo"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Ui.Label {
                Layout.fillWidth: true
                role: "headline"
                elide: Text.ElideRight
                maximumLineCount: root.share?.kind === "text" ? 2 : 1
                wrapMode: root.share?.kind === "text" ? Text.Wrap : Text.NoWrap
                text: {
                    const items = root.share?.items ?? [];
                    if (root.share?.kind === "text")
                        return items[0] ?? "";
                    return items.length === 1 ? items[0] : items.length + " items";
                }
            }

            Ui.Label {
                Layout.fillWidth: true
                role: "caption"
                color: Theme.textSecondary
                text: root.share?.kind === "text" ? "Text" : root.share?.kind === "links" ? "Link" : (root.share?.items.length ?? 0) === 1 ? "File" : "Files"
            }
        }
    }

    Flow {
        Layout.fillWidth: true
        visible: root.step === "share" && (root.share?.receivers.length ?? 0) > 0
        spacing: Metrics.s2

        Repeater {
            model: root.share?.receivers ?? []

            // One nearby device: its initials in a circle that fills as the
            // share goes to it, its name, and how sending is going.
            Ui.Pressable {
                id: receiver

                required property var modelData
                readonly property var sending: root.share?.sending ?? null
                readonly property bool target: sending !== null && sending.to === receiver.modelData.name
                readonly property string state_: target ? sending.state : ""

                width: 92
                height: column.implicitHeight + Metrics.s2 * 2
                radius: Metrics.rCard
                interactive: receiver.sending === null || ["sent", "declined", "failed"].indexOf(receiver.sending.state) >= 0
                pressScale: 0.94
                onClicked: Sys.AirDrop.send(receiver.modelData.id)

                ColumnLayout {
                    id: column

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: Metrics.s2
                    width: parent.width - Metrics.s2 * 2
                    spacing: Metrics.s1

                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 60
                        implicitHeight: 60

                        Rectangle {
                            anchors.centerIn: parent
                            width: 50
                            height: 50
                            radius: 25
                            color: Theme.accentSoft

                            Ui.Label {
                                anchors.centerIn: parent
                                text: root.initials(receiver.modelData.name)
                                role: "headline"
                                color: Theme.accent
                            }
                        }

                        Ui.Ring {
                            anchors.fill: parent
                            visible: receiver.target
                            thickness: 3
                            track: receiver.state_ === "sending" ? Theme.fillTrack : "transparent"
                            busy: receiver.state_ === "asking"
                            fraction: receiver.state_ === "sending" ? (receiver.sending.total > 0 ? receiver.sending.sent / receiver.sending.total : 0) : 1
                            color: receiver.state_ === "declined" || receiver.state_ === "failed" ? Theme.critical : receiver.state_ === "sent" ? Theme.positive : Theme.accent
                        }
                    }

                    Ui.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        role: "caption"
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        text: receiver.modelData.name
                    }

                    Ui.Label {
                        Layout.fillWidth: true
                        visible: receiver.target
                        horizontalAlignment: Text.AlignHCenter
                        role: "caption"
                        color: receiver.state_ === "declined" || receiver.state_ === "failed" ? Theme.critical : Theme.textSecondary
                        elide: Text.ElideRight
                        text: {
                            switch (receiver.state_) {
                            case "asking":
                                return "Waiting…";
                            case "sending":
                                return "Sending…";
                            case "sent":
                                return "Sent";
                            case "declined":
                                return "Declined";
                            }
                            return receiver.sending?.error || "Failed";
                        }
                    }
                }
            }
        }
    }

    // Nobody yet: the radar sweeps while iPhones wake up to the advert.
    ColumnLayout {
        Layout.fillWidth: true
        visible: root.step === "share" && (root.share?.receivers.length ?? 0) === 0
        spacing: Metrics.s2

        Ui.Icon {
            Layout.alignment: Qt.AlignHCenter
            name: "radar"
            size: 32
            color: Theme.accent

            SequentialAnimation on opacity {
                running: root.shown && root.step === "share"
                loops: Animation.Infinite

                NumberAnimation {
                    to: 0.35
                    duration: 900
                    easing.type: Easing.InOutSine
                }
                NumberAnimation {
                    to: 1
                    duration: 900
                    easing.type: Easing.InOutSine
                }
            }
        }

        Ui.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            role: "callout"
            color: Theme.textSecondary
            text: Sys.AirDrop.busy ? "Starting AirDrop…" : "Looking for iPhones nearby. They need to be unlocked, with AirDrop set to Everyone for 10 Minutes."
        }
    }

    Ui.Label {
        Layout.fillWidth: true
        visible: Sys.AirDrop.pausesWifi && (root.step === "share" || root.step === "offer")
        horizontalAlignment: root.step === "share" ? Text.AlignHCenter : Text.AlignLeft
        wrapMode: Text.WordWrap
        role: "caption"
        color: Theme.textTertiary
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
