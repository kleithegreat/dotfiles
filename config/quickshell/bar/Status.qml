import QtQuick
import qs
import qs.ui as Ui
import qs.services as Sys

// Network, bluetooth, sound, brightness and battery are one control, not five.
// They open the same surface, so they get one hover shape and one hit target;
// five adjacent buttons that all do the same thing is a menu bar pretending to
// be a dashboard.
BarItem {
    id: root

    contentWidth: glyphs.implicitWidth

    Row {
        id: glyphs
        anchors.centerIn: parent
        spacing: Metrics.s2 - 1

        Ui.Signal {
            anchors.verticalCenter: parent.verticalCenter
            size: Metrics.barIcon
            strength: Sys.Network.signal
            visible: Sys.Network.linkType === "wifi"
            color: Sys.Network.captivePortal ? Theme.caution : root.hovered ? Theme.text : Theme.textSecondary
        }

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            size: Metrics.barIcon
            name: Sys.Network.icon
            visible: Sys.Network.linkType !== "wifi"
            color: Sys.Network.captivePortal ? Theme.caution : root.hovered ? Theme.text : Theme.textSecondary
        }

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            size: Metrics.barIcon
            name: Sys.Bluetooth.icon
            visible: Sys.Bluetooth.available
            color: Sys.Bluetooth.connected.length > 0 ? Theme.accent : root.hovered ? Theme.text : Theme.textSecondary
        }

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            size: Metrics.barIcon
            name: Sys.Audio.icon
            color: Sys.Audio.muted ? Theme.textQuaternary : root.hovered ? Theme.text : Theme.textSecondary
        }

        Ui.Icon {
            anchors.verticalCenter: parent.verticalCenter
            size: Metrics.barIcon
            name: Sys.Brightness.icon
            visible: Sys.Brightness.available
            color: root.hovered ? Theme.text : Theme.textSecondary
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: Metrics.s1 - 1
            visible: Sys.Power.present

            Ui.Icon {
                anchors.verticalCenter: parent.verticalCenter
                name: Sys.Power.icon
                color: Sys.Power.low ? Theme.critical : Sys.Power.charging ? Theme.positive : root.hovered ? Theme.text : Theme.textSecondary
            }

            Ui.Label {
                anchors.verticalCenter: parent.verticalCenter
                text: Sys.Power.percent
                role: "caption"
                numeric: true
                font.weight: Theme.weightMedium
                color: Sys.Power.low ? Theme.critical : Theme.textSecondary
            }
        }
    }
}
