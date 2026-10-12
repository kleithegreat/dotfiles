import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    readonly property string phase: Sys.Fingerprint.phase

    readonly property var prompts: ({
        "": "Rest your finger on the sensor",
        "enroll-stage-passed": "Lift, then rest your finger again",
        "enroll-retry-scan": "That one didn't register. Try again",
        "enroll-swipe-too-short": "Hold your finger a little longer",
        "enroll-finger-not-centered": "Centre your finger on the sensor",
        "enroll-remove-and-retry": "Lift your finger and try again",
        "enroll-duplicate": "This finger is already added",
        "enroll-data-full": "The reader has no room for another fingerprint",
        "enroll-disconnected": "The reader disconnected"
    })

    function labelOf(id) {
        const fingers = Sys.Fingerprint.fingers;
        for (let i = 0; i < fingers.length; i++) {
            if (fingers[i].id === id)
                return fingers[i].label;
        }
        return "";
    }

    Component.onCompleted: Sys.Fingerprint.refresh()

    ColumnLayout {
        id: body
        width: root.width
        spacing: Metrics.s4

        Ui.Card {
            Layout.fillWidth: true
            implicitHeight: enrolment.implicitHeight + Metrics.s5 * 2
            visible: root.phase !== ""

            ColumnLayout {
                id: enrolment
                anchors.centerIn: parent
                width: parent.width - Metrics.s5 * 2
                spacing: Metrics.s2

                Item {
                    id: glyph

                    readonly property int size: Metrics.s8 * 2

                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: Metrics.s2
                    implicitWidth: size
                    implicitHeight: size

                    Ui.Icon {
                        name: "fingerprint"
                        size: glyph.size
                        color: Theme.textQuaternary
                        opacity: 0.45
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: glyph.size * (root.phase === "failed" ? 1 : Sys.Fingerprint.fraction)
                        clip: true

                        Behavior on height {
                            Ui.Anim {
                                duration: Motion.settled
                            }
                        }

                        Ui.Icon {
                            anchors.bottom: parent.bottom
                            name: "fingerprint"
                            size: glyph.size
                            color: root.phase === "failed" ? Theme.critical : Theme.accent
                        }
                    }

                    SequentialAnimation {
                        id: pulse

                        Ui.Anim {
                            target: glyph
                            property: "scale"
                            to: 1.07
                            duration: Motion.instant
                        }
                        Ui.Anim {
                            target: glyph
                            property: "scale"
                            to: 1
                            duration: Motion.settled
                        }
                    }

                    Connections {
                        target: Sys.Fingerprint
                        function onCapturedChanged() {
                            if (Sys.Fingerprint.captured > 0)
                                pulse.restart();
                        }
                    }
                }

                Ui.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    role: "headline"
                    text: root.phase === "done" ? "Fingerprint added" : root.prompts[Sys.Fingerprint.result] || (root.phase === "failed" ? "Couldn't add this fingerprint" : root.prompts[""])
                }

                Ui.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    role: "caption"
                    numeric: true
                    text: root.labelOf(Sys.Fingerprint.finger) + (root.phase === "scanning" && Sys.Fingerprint.stages > 0 ? " · " + Sys.Fingerprint.captured + " of " + Sys.Fingerprint.stages : "")
                }

                Ui.Button {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Metrics.s2
                    text: root.phase === "scanning" ? "Cancel" : "Done"
                    variant: root.phase === "scanning" ? "plain" : "tinted"
                    onClicked: root.phase === "scanning" ? Sys.Fingerprint.cancel() : Sys.Fingerprint.dismiss()
                }
            }
        }

        Ui.Group {
            title: "Fingerprints"

            Repeater {
                model: Sys.Fingerprint.fingers

                Ui.ListRow {
                    id: finger

                    required property var modelData
                    readonly property bool present: Sys.Fingerprint.has(modelData.id)

                    Layout.fillWidth: true
                    icon: "fingerprint"
                    iconColor: finger.present ? Theme.accent : Theme.textSecondary
                    title: modelData.label
                    subtitle: finger.present ? "Added" : ""
                    interactive: false

                    Ui.Button {
                        anchors.verticalCenter: parent.verticalCenter
                        text: finger.present ? "Remove" : "Add"
                        variant: finger.present ? "plain" : "tinted"
                        interactive: !Sys.Fingerprint.busy && root.phase === ""
                        onClicked: finger.present ? Sys.Fingerprint.forget(finger.modelData.id) : Sys.Fingerprint.start(finger.modelData.id)
                    }
                }
            }
        }
    }
}
