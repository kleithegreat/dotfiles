import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    Component.onCompleted: Sys.Fingerprint.refresh()

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Group {
            title: "Fingerprints"
            footnote: Sys.Fingerprint.status

            Repeater {
                model: Sys.Fingerprint.fingers

                Ui.ListRow {
                    id: finger

                    required property var modelData
                    readonly property bool present: Sys.Fingerprint.has(modelData.id)

                    Layout.fillWidth: true
                    icon: "certificate"
                    iconColor: finger.present ? Theme.accent : Theme.textSecondary
                    title: modelData.label
                    subtitle: Sys.Fingerprint.enrolling === modelData.id ? "Touch the reader" : finger.present ? "Enrolled" : ""
                    interactive: false

                    Ui.Button {
                        anchors.verticalCenter: parent.verticalCenter
                        text: finger.present ? "Remove" : "Enrol"
                        variant: finger.present ? "plain" : "tinted"
                        interactive: !Sys.Fingerprint.busy
                        onClicked: finger.present ? Sys.Fingerprint.forget(finger.modelData.id) : Sys.Fingerprint.start(finger.modelData.id)
                    }
                }
            }
        }
    }
}
