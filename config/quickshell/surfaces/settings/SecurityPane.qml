import QtQuick
import QtQuick.Layouts
import qs
import qs.ui as Ui
import qs.services as Sys

Ui.Scroll {
    id: root

    contentHeight: body.height

    // One enrolment card serves both; only one can run at a time.
    readonly property bool faceShown: Sys.Face.phase !== ""
    readonly property string phase: faceShown ? Sys.Face.phase : Sys.Fingerprint.phase

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

    function headline() {
        if (faceShown)
            return phase === "done" ? "Face added" : phase === "failed" ? Sys.Face.result || "Couldn't add your face" : "Look at the camera";
        return phase === "done" ? "Fingerprint added" : prompts[Sys.Fingerprint.result] || (phase === "failed" ? "Couldn't add this fingerprint" : prompts[""]);
    }

    function caption() {
        if (faceShown)
            return phase === "scanning" ? "Hold still for a few seconds" : "";
        return labelOf(Sys.Fingerprint.finger) + (phase === "scanning" && Sys.Fingerprint.stages > 0 ? " · " + Sys.Fingerprint.captured + " of " + Sys.Fingerprint.stages : "");
    }

    Component.onCompleted: {
        Sys.Fingerprint.refresh();
        if (Sys.Host.face)
            Sys.Face.refresh();
    }

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
                    readonly property string icon: root.faceShown ? "face-id" : "fingerprint"

                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: Metrics.s2
                    implicitWidth: size
                    implicitHeight: size

                    Ui.Icon {
                        name: glyph.icon
                        size: glyph.size
                        color: Theme.textQuaternary
                        opacity: 0.45
                    }

                    Item {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: glyph.size * (root.phase === "failed" || root.phase === "done" ? 1 : root.faceShown ? 0 : Sys.Fingerprint.fraction)
                        clip: true

                        Behavior on height {
                            Ui.Anim {
                                duration: Motion.settled
                            }
                        }

                        Ui.Icon {
                            anchors.bottom: parent.bottom
                            name: glyph.icon
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

                    // A face scan reports nothing until it ends, so it breathes instead.
                    SequentialAnimation {
                        running: root.faceShown && root.phase === "scanning"
                        loops: Animation.Infinite
                        alwaysRunToEnd: true

                        Ui.Anim {
                            target: glyph
                            property: "scale"
                            to: 1.07
                            duration: Motion.settled
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
                    text: root.headline()
                }

                Ui.Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    role: "caption"
                    numeric: true
                    text: root.caption()
                    visible: text !== ""
                }

                Ui.Button {
                    readonly property bool cancels: root.phase === "scanning"

                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: Metrics.s2
                    visible: !(cancels && root.faceShown)
                    text: cancels ? "Cancel" : "Done"
                    variant: cancels ? "plain" : "tinted"
                    onClicked: root.faceShown ? Sys.Face.dismiss() : cancels ? Sys.Fingerprint.cancel() : Sys.Fingerprint.dismiss()
                }
            }
        }

        Ui.Group {
            title: "Face"
            footnote: "Unlocks the lock screen and sudo. The login screen still takes your password."
            visible: Sys.Host.face

            Repeater {
                model: Sys.Face.models

                Ui.ListRow {
                    id: face

                    required property var modelData

                    Layout.fillWidth: true
                    icon: "face-id"
                    iconColor: Theme.accent
                    title: modelData.label
                    subtitle: "Added " + Qt.formatDate(new Date(modelData.time.replace(" ", "T")), "d MMMM yyyy")
                    interactive: false

                    Ui.Button {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Remove"
                        variant: "plain"
                        interactive: !Sys.Face.busy && root.phase === ""
                        onClicked: Sys.Face.forget(face.modelData.id)
                    }
                }
            }

            Ui.ListRow {
                Layout.fillWidth: true
                icon: "face-id"
                title: Sys.Face.models.length > 0 ? "Add another look" : "Add your face"
                subtitle: Sys.Face.models.length > 0 ? "With glasses, say, or in different light" : ""
                interactive: false

                Ui.Button {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Add"
                    variant: "tinted"
                    interactive: !Sys.Face.busy && root.phase === ""
                    onClicked: Sys.Face.start()
                }
            }
        }

        Ui.Group {
            title: "Fingerprints"
            visible: Sys.Host.fingerprint

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
