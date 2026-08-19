import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    property string prompting: ""
    property string promptKind: ""

    Component.onCompleted: {
        Sys.Network.scan();
        Sys.Mullvad.loadRelays();
    }

    Connections {
        target: Sys.Network

        function onConnectSucceeded() {
            root.prompting = "";
        }
    }

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            Ui.ListRow {
                Layout.fillWidth: true
                icon: Sys.Network.icon
                title: "Wi-Fi"
                subtitle: Sys.Network.wifiRadio ? Sys.Network.label : "Off"
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Network.wifiRadio
                    pending: Sys.Network.radioBusy
                    onToggled: Sys.Network.toggleWifiRadio()
                }
            }
        }

        Ui.Group {
            title: "Connection"
            visible: Sys.Network.online

            Ui.ListRow {
                Layout.fillWidth: true
                icon: Sys.Network.linkType === "ethernet" ? "ethernet" : "router"
                title: Sys.Network.label
                subtitle: Sys.Network.linkType === "ethernet" ? (Sys.Network.ethernetSpeed !== "" ? Sys.Network.ethernetSpeed + " Mb/s · " + Sys.Network.ethernetDuplex : "Wired") : Sys.Network.signal + "% signal · " + Sys.Network.frequency
                interactive: false

                Ui.Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Disconnect"
                    visible: Sys.Network.linkType === "wifi"
                    onClicked: Sys.Network.disconnect()
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "world"
                title: "IP address"
                interactive: false

                Ui.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Sys.Network.ipAddress
                    role: "callout"
                    numeric: true
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "router"
                title: "Router"
                interactive: false

                Ui.Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Sys.Network.gateway
                    role: "callout"
                    numeric: true
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "stethoscope"
                title: "DNS"
                subtitle: Sys.Network.dns
                interactive: false

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s1

                    Repeater {
                        model: [{ label: "Auto", value: "auto" }, { label: "Cloudflare", value: "1.1.1.1" }, { label: "Quad9", value: "9.9.9.9" }]

                        Ui.Button {
                            required property var modelData
                            text: modelData.label
                            variant: "plain"
                            onClicked: Sys.Network.setDns(modelData.value)
                        }
                    }
                }
            }
        }

        Ui.Group {
            title: Sys.Network.scanning ? "Networks · scanning" : "Networks"
            visible: Sys.Network.wifiRadio

            Repeater {
                model: Sys.Network.networks

                ColumnLayout {
                    id: entry

                    required property string ssid
                    required property int signal
                    required property string security
                    required property bool active

                    Layout.fillWidth: true
                    spacing: 0

                    Ui.ListRow {
                        Layout.fillWidth: true
                        leading: Component {
                            Ui.Signal {
                                strength: entry.signal
                                color: entry.active ? Theme.accent : Theme.textSecondary
                            }
                        }
                        title: entry.ssid
                        subtitle: entry.active ? "Connected" : Sys.Network.isKnown(entry.ssid) ? "Saved" : ""
                        onClicked: {
                            if (entry.active)
                                return;
                            const need = Sys.Network.connect(entry.ssid, entry.security);
                            root.prompting = need === "" ? "" : entry.ssid;
                            root.promptKind = need;
                        }

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Metrics.s2

                            Ui.Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "lock"
                                size: Metrics.iconSm
                                color: Theme.textQuaternary
                                visible: entry.security !== ""
                            }

                            Ui.Button {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Forget"
                                visible: Sys.Network.isKnown(entry.ssid) && !entry.active
                                onClicked: Sys.Network.forget(entry.ssid)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: Metrics.rowInset
                        Layout.rightMargin: Metrics.rowInset
                        Layout.bottomMargin: Metrics.s2
                        spacing: Metrics.s2
                        visible: root.prompting === entry.ssid

                        Ui.Field {
                            id: identity
                            Layout.fillWidth: true
                            placeholder: "Username"
                            visible: root.promptKind === "enterprise"
                        }

                        Ui.Field {
                            id: secret
                            Layout.fillWidth: true
                            placeholder: "Password"
                            echo: TextInput.Password
                            onAccepted: submit.clicked()
                        }

                        Ui.Button {
                            id: submit
                            text: "Join"
                            variant: "filled"
                            onClicked: {
                                if (root.promptKind === "enterprise")
                                    Sys.Network.connectEnterprise(entry.ssid, identity.text, secret.text);
                                else
                                    Sys.Network.connectWithPassword(entry.ssid, secret.text);
                                secret.text = "";
                            }
                        }
                    }
                }
            }
        }

        Ui.Group {
            title: "Mullvad"
            footnote: Sys.Mullvad.connected ? "Exit IP " + Sys.Mullvad.ip : ""

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "shield-lock"
                iconColor: Sys.Mullvad.connected ? Theme.accent : Theme.textSecondary
                title: "Mullvad VPN"
                subtitle: Sys.Mullvad.connected ? Sys.Mullvad.location : Sys.Mullvad.state
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Mullvad.connected
                    pending: Sys.Mullvad.busy
                    onToggled: Sys.Mullvad.toggle()
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "world"
                title: "Location"
                subtitle: Sys.Mullvad.selectedLabel
                chevron: true
                onClicked: relays.open = !relays.open
            }

            ColumnLayout {
                id: relays
                property bool open: false

                Layout.fillWidth: true
                Layout.leftMargin: Metrics.rowInset
                spacing: 0
                visible: open

                Repeater {
                    model: relays.open ? Sys.Mullvad.relays : []

                    Ui.ListRow {
                        required property var modelData
                        Layout.fillWidth: true
                        title: modelData.name
                        subtitle: modelData.cities.length + " cities"
                        selected: Sys.Mullvad.selectedCountry === modelData.code
                        onClicked: Sys.Mullvad.setLocation(modelData.code)
                    }
                }
            }
        }

        Ui.Group {
            title: "Tailscale"
            footnote: Sys.Tailscale.up ? Sys.Tailscale.tailnet : ""

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "tailscale"
                iconColor: Sys.Tailscale.up ? Theme.accent : Theme.textSecondary
                title: "Tailscale"
                subtitle: Sys.Tailscale.up ? Sys.Tailscale.ip : Sys.Tailscale.state
                interactive: false

                Ui.Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: Sys.Tailscale.up
                    pending: Sys.Tailscale.busy
                    onToggled: Sys.Tailscale.toggle()
                }
            }
        }
    }
}
