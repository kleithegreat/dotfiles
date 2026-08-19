import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

// Measurements grouped by the question they answer, each group stating its
// conclusion before its numbers. The old pane put twenty figures on screen at
// once and left the reader to work out which of them meant the network was bad.
Ui.Scroll {
    id: root

    contentHeight: body.height

    Component.onCompleted: {
        Sys.NetworkProbe.active = true;
        Sys.NetworkProbe.surveyChannels();
    }
    Component.onDestruction: Sys.NetworkProbe.active = false

    function verdict(value, good, fair) {
        if (value < 0)
            return { label: "Not measured", color: Theme.textTertiary };
        if (value <= good)
            return { label: "Good", color: Theme.positive };
        if (value <= fair)
            return { label: "Fair", color: Theme.caution };
        return { label: "Poor", color: Theme.critical };
    }

    function strength(value, good, fair) {
        if (value < 0)
            return { label: "Not measured", color: Theme.textTertiary };
        if (value >= good)
            return { label: "Good", color: Theme.positive };
        if (value >= fair)
            return { label: "Fair", color: Theme.caution };
        return { label: "Weak", color: Theme.critical };
    }

    function ms(value) {
        return value < 0 ? "—" : value.toFixed(1) + " ms";
    }

    readonly property var latency: {
        const worst = Math.max(Sys.NetworkProbe.gatewayLoss, Sys.NetworkProbe.internetLoss);
        if (worst > 2)
            return { label: "Packet loss", color: Theme.critical };
        return verdict(Sys.NetworkProbe.internetPing, 40, 90);
    }

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            title: "Link"
            visible: Sys.Network.linkType === "wifi"

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Signal"
                subtitle: Sys.NetworkProbe.band + (Sys.NetworkProbe.channel > 0 ? " · channel " + Sys.NetworkProbe.channel : "") + (Sys.NetworkProbe.linkRate !== "" ? " · " + Sys.NetworkProbe.linkRate : "")
                interactive: false

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3

                    Ui.Sparkline {
                        samples: Sys.NetworkProbe.signalHistory
                        stroke: root.strength(Sys.NetworkProbe.signal, 65, 40).color
                    }

                    Ui.Label {
                        text: Sys.NetworkProbe.signal < 0 ? "—" : Sys.NetworkProbe.signal + "%"
                        role: "callout"
                        numeric: true
                        color: root.strength(Sys.NetworkProbe.signal, 65, 40).color
                    }
                }
            }
        }

        Ui.Group {
            title: "Latency"

            Ui.ListRow {
                Layout.fillWidth: true
                title: root.latency.label
                iconColor: root.latency.color
                icon: "radar"
                interactive: false
                subtitle: Sys.NetworkProbe.measuring ? "Measuring" : "Five packets to each hop, every six seconds"
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Router"
                subtitle: "jitter " + root.ms(Sys.NetworkProbe.gatewayJitter) + (Sys.NetworkProbe.gatewayLoss > 0 ? " · " + Sys.NetworkProbe.gatewayLoss + "% loss" : "")
                interactive: false

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3

                    Ui.Sparkline {
                        samples: Sys.NetworkProbe.gatewayHistory
                        stroke: root.verdict(Sys.NetworkProbe.gatewayPing, 5, 20).color
                    }

                    Ui.Label {
                        text: root.ms(Sys.NetworkProbe.gatewayPing)
                        role: "callout"
                        numeric: true
                    }
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
            }

            Ui.ListRow {
                Layout.fillWidth: true
                title: "Internet"
                subtitle: "jitter " + root.ms(Sys.NetworkProbe.internetJitter) + (Sys.NetworkProbe.internetLoss > 0 ? " · " + Sys.NetworkProbe.internetLoss + "% loss" : "")
                interactive: false

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3

                    Ui.Sparkline {
                        samples: Sys.NetworkProbe.internetHistory
                        stroke: root.verdict(Sys.NetworkProbe.internetPing, 40, 90).color
                    }

                    Ui.Label {
                        text: root.ms(Sys.NetworkProbe.internetPing)
                        role: "callout"
                        numeric: true
                    }
                }
            }
        }

        Ui.Group {
            title: "DNS"

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "stethoscope"
                iconColor: root.verdict(Sys.NetworkProbe.dnsTime, 30, 90).color
                title: root.verdict(Sys.NetworkProbe.dnsTime, 30, 90).label
                subtitle: Sys.NetworkProbe.dnsServer !== "" ? Sys.NetworkProbe.dnsServer : "No resolver reported"
                interactive: false

                RowLayout {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Metrics.s3

                    Ui.Sparkline {
                        samples: Sys.NetworkProbe.dnsHistory
                        stroke: root.verdict(Sys.NetworkProbe.dnsTime, 30, 90).color
                    }

                    Ui.Label {
                        text: Sys.NetworkProbe.dnsTime < 0 ? "—" : Math.round(Sys.NetworkProbe.dnsTime) + " ms"
                        role: "callout"
                        numeric: true
                    }
                }
            }
        }

        Ui.Group {
            title: "Throughput"
            footnote: Sys.NetworkProbe.bloat > 0 ? "Latency under load rose from " + root.ms(Sys.NetworkProbe.idleLatency) + " to " + root.ms(Sys.NetworkProbe.loadedLatency) + "." : "A speed test saturates the link for about half a minute."

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "speed"
                title: Sys.NetworkProbe.download < 0 ? "Not measured" : Math.round(Sys.NetworkProbe.download) + " Mb/s down · " + Math.round(Sys.NetworkProbe.upload) + " Mb/s up"
                subtitle: Sys.NetworkProbe.testingSpeed ? "Running" : Sys.NetworkProbe.bloat > 0 ? "Bufferbloat " + Sys.NetworkProbe.bloat.toFixed(1) + "×" : ""
                interactive: false

                Ui.Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Sys.NetworkProbe.testingSpeed ? "Testing" : "Run test"
                    variant: "tinted"
                    interactive: !Sys.NetworkProbe.testingSpeed
                    onClicked: Sys.NetworkProbe.runSpeedTest()
                }
            }

            Ui.Divider {
                inset: Metrics.rowInset
                visible: Sys.NetworkProbe.bloat > 0
            }

            Ui.ListRow {
                Layout.fillWidth: true
                visible: Sys.NetworkProbe.bloat > 0
                icon: "hourglass"
                iconColor: root.verdict(Sys.NetworkProbe.bloat, 1.3, 2.0).color
                title: "Responsiveness under load"
                subtitle: root.verdict(Sys.NetworkProbe.bloat, 1.3, 2.0).label
                interactive: false
            }
        }

        Ui.Group {
            title: "Nearby channels"
            visible: Sys.Network.linkType === "wifi"
            footnote: "How many networks share each channel, and how loud the strongest one is."

            Repeater {
                model: Sys.NetworkProbe.survey

                Ui.ListRow {
                    id: chan

                    required property var modelData

                    Layout.fillWidth: true
                    title: "Channel " + chan.modelData.channel
                    subtitle: chan.modelData.count + (chan.modelData.count === 1 ? " network" : " networks")
                    interactive: false
                    tint: chan.modelData.channel === Sys.NetworkProbe.channel ? Theme.accentSoft : "transparent"

                    RowLayout {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Metrics.s3

                        Rectangle {
                            width: 90
                            height: 5
                            radius: 2.5
                            color: Theme.fillTrack
                            antialiasing: true

                            Rectangle {
                                width: parent.width * Math.min(1, chan.modelData.strongest / 100)
                                height: parent.height
                                radius: parent.radius
                                color: chan.modelData.channel === Sys.NetworkProbe.channel ? Theme.accent : Theme.textQuaternary
                                antialiasing: true
                            }
                        }

                        Ui.Label {
                            text: chan.modelData.strongest + "%"
                            role: "caption"
                            numeric: true
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: Metrics.s8
                        }
                    }
                }
            }
        }
    }
}
