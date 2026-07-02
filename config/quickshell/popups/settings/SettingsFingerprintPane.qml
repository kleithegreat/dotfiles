import qs
import QtQuick
import QtQuick.Layouts
import "../../components" as Components

Components.WheelFlickable {
    id: root
    required property bool stateLoading
    required property string deviceName
    required property var enrolledFingers
    required property string runtimeError
    required property bool actionBusy
    required property string actionMode
    required property string actionFinger
    required property string actionStatus
    required property string actionError
    required property string actionTone
    required property int enrollStagesCompleted
    required property int enrollStagesTotal
    required property string enrollScanType

    signal refreshRequested()
    signal enrollRequested(string finger)
    signal deleteRequested(string finger)
    signal cancelRequested()

    property string selectedEnrolledFinger: ""

    readonly property int enrolledCount: Array.isArray(root.enrolledFingers) ? root.enrolledFingers.length : 0
    readonly property var fingerBaseSlots: [
        { key: "thumb", label: "Thumb" },
        { key: "index-finger", label: "Index Finger" },
        { key: "middle-finger", label: "Middle Finger" },
        { key: "ring-finger", label: "Ring Finger" },
        { key: "little-finger", label: "Little Finger" }
    ]
    readonly property var leftFingerSlots: root.fingerBaseSlots.map((slot) => ({ key: "left-" + slot.key, label: "Left " + slot.label }))
    readonly property var rightFingerSlots: root.fingerBaseSlots.map((slot) => ({ key: "right-" + slot.key, label: "Right " + slot.label }))
    readonly property var allFingerSlots: root.leftFingerSlots.concat(root.rightFingerSlots)
    readonly property var handSections: [
        { title: "Left Hand", fingers: root.leftFingerSlots },
        { title: "Right Hand", fingers: root.rightFingerSlots }
    ]
    readonly property bool enrollmentActive: root.actionBusy && root.actionMode === "enroll"
    readonly property int visualEnrollStages: root.enrollStagesTotal > 0 ? root.enrollStagesTotal : 12
    readonly property color enrollAccent: root.actionTone === "retry" ? Theme.orangeBright : Theme.blueBright
    readonly property string statusText: root.actionError !== ""
        ? root.actionError
        : (root.runtimeError !== "" ? root.runtimeError : root.actionStatus)
    readonly property color statusColor: root.actionError !== "" || root.runtimeError !== ""
        ? Theme.redBright
        : (root.actionBusy ? root.enrollAccent : Theme.greenBright)

    anchors.fill: parent
    contentHeight: fingerprintCol.implicitHeight
    clip: true

    onEnrolledFingersChanged: {
        if (root.selectedEnrolledFinger !== "" && !root.isEnrolled(root.selectedEnrolledFinger))
            root.selectedEnrolledFinger = "";
    }

    function isEnrolled(finger) {
        return Array.isArray(root.enrolledFingers) && root.enrolledFingers.indexOf(finger) !== -1;
    }

    function fingerLabel(finger) {
        let slots = root.allFingerSlots;
        for (let i = 0; i < slots.length; i++) {
            if (slots[i].key === finger)
                return slots[i].label;
        }

        return finger;
    }

    function summaryText() {
        if (root.stateLoading)
            return "Checking enrolled fingerprints...";
        if (root.enrolledCount === 0)
            return "No fingerprints enrolled";
        if (root.enrolledCount === 1)
            return "1 fingerprint enrolled";
        return root.enrolledCount + " fingerprints enrolled";
    }

    function fingerStatusText(finger) {
        if (root.actionBusy && root.actionFinger === finger) {
            if (root.actionMode === "delete")
                return "Removing...";
            if (root.enrollStagesTotal > 0)
                return "Capture " + root.enrollStagesCompleted + " / " + root.enrollStagesTotal;
            return root.enrollScanType === "swipe" ? "Swipe sensor repeatedly" : "Touch sensor repeatedly";
        }
        if (root.selectedEnrolledFinger === finger)
            return "Selected for removal";
        return root.isEnrolled(finger) ? "Enrolled" : "Click to enroll";
    }

    function enrollmentSummaryText() {
        if (root.enrollStagesTotal > 0)
            return root.enrollStagesCompleted + " of " + root.enrollStagesTotal + " captures recorded";
        return "Recording fingerprint samples";
    }

    function enrollmentGuidanceText() {
        return root.enrollScanType === "swipe"
            ? "Swipe the same finger across the reader from slightly different angles each time."
            : "Lift and reposition the same finger between touches so the reader captures different angles.";
    }

    function activateFinger(finger) {
        if (root.actionBusy || root.stateLoading)
            return;

        if (root.isEnrolled(finger)) {
            root.selectedEnrolledFinger = root.selectedEnrolledFinger === finger ? "" : finger;
            return;
        }

        root.selectedEnrolledFinger = "";
        root.enrollRequested(finger);
    }

    ColumnLayout {
        id: fingerprintCol
        width: parent.width
        spacing: 16

        Components.SettingsPaneHeader { title: "Fingerprint"; iconSource: "../icons/shield-lock.svg" }

        Rectangle {
            id: summaryCard
            Layout.fillWidth: true
            implicitHeight: summaryRow.implicitHeight + 28
            radius: Theme.popupRadius
            color: Theme.bg1
            border.width: 1
            border.color: Theme.bg3

            RowLayout {
                id: summaryRow
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Rectangle {
                    width: 38
                    height: 38
                    radius: 19
                    color: Qt.alpha(Theme.accent, 0.14)

                    Components.Icon {
                        anchors.centerIn: parent
                        source: "../icons/shield-lock.svg"
                        color: Theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    Text {
                        text: root.summaryText()
                        color: Theme.fg
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.deviceName !== "" ? root.deviceName : "Fingerprint reader"
                        color: Theme.fg3
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                }

                Rectangle {
                    width: 36
                    height: 36
                    radius: Theme.btnRadius
                    opacity: (root.stateLoading || root.actionBusy) ? 0.45 : 1
                    color: refreshArea.containsMouse && !refreshArea.disabled ? Theme.bg2 : Theme.bg
                    border.width: 1
                    border.color: Theme.bg3
                    Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                    Behavior on opacity { Components.Anim { duration: Theme.animHover } }

                    Components.Icon {
                        anchors.centerIn: parent
                        source: "../icons/refresh.svg"
                        color: Theme.fg3
                    }

                    Components.HoverLayer {
                        id: refreshArea
                        disabled: root.stateLoading || root.actionBusy
                        flat: true
                        onClicked: root.refreshRequested()
                    }
                }
            }
        }

        Rectangle {
            id: enrollCard
            visible: root.enrollmentActive
            Layout.fillWidth: true
            implicitHeight: enrollCol.implicitHeight + 28
            radius: Theme.popupRadius
            color: Qt.alpha(root.enrollAccent, 0.08)
            border.width: 1
            border.color: root.enrollAccent

            ColumnLayout {
                id: enrollCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Text {
                    text: "Enrolling " + root.fingerLabel(root.actionFinger)
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 188
                    Layout.preferredHeight: 188

                    Repeater {
                        model: root.visualEnrollStages

                        delegate: Rectangle {
                            required property int index

                            readonly property real angle: (-Math.PI / 2) + (index * ((Math.PI * 2) / root.visualEnrollStages))
                            readonly property bool completed: index < root.enrollStagesCompleted
                            readonly property bool nextStage: !completed && index === root.enrollStagesCompleted

                            width: 16
                            height: 6
                            radius: 3
                            color: completed ? root.enrollAccent : (nextStage ? Qt.alpha(root.enrollAccent, 0.55) : Theme.bg3)
                            opacity: completed ? 1 : (nextStage ? 0.9 : 0.5)
                            x: (parent.width / 2) + (Math.cos(angle) * 76) - (width / 2)
                            y: (parent.height / 2) + (Math.sin(angle) * 76) - (height / 2)
                            rotation: (angle * 180 / Math.PI) + 90
                            transformOrigin: Item.Center
                            Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                            Behavior on opacity { Components.Anim { duration: Theme.animHover } }
                        }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 118
                        height: 118
                        radius: 59
                        color: Qt.alpha(root.enrollAccent, 0.12)
                        border.width: 1
                        border.color: root.enrollAccent

                        Rectangle {
                            anchors.centerIn: parent
                            width: 90
                            height: 90
                            radius: 45
                            color: Theme.bg
                            border.width: 1
                            border.color: Theme.bg3
                        }

                        Rectangle {
                            id: enrollPulse
                            anchors.centerIn: parent
                            width: 94
                            height: 94
                            radius: 47
                            color: "transparent"
                            border.width: 1
                            border.color: root.enrollAccent
                            opacity: 0.18
                            scale: 0.94

                            SequentialAnimation on scale {
                                running: root.enrollmentActive
                                loops: Animation.Infinite
                                Components.Anim { from: 0.94; to: 1.02; duration: 1000; easing.type: Easing.InOutQuad }
                                Components.Anim { from: 1.02; to: 0.94; duration: 1000; easing.type: Easing.InOutQuad }
                            }

                            SequentialAnimation on opacity {
                                running: root.enrollmentActive
                                loops: Animation.Infinite
                                Components.Anim { from: 0.12; to: 0.24; duration: 1000; easing.type: Easing.InOutQuad }
                                Components.Anim { from: 0.24; to: 0.12; duration: 1000; easing.type: Easing.InOutQuad }
                            }
                        }

                        Item {
                            anchors.centerIn: parent
                            width: 88
                            height: 88
                            clip: true

                            Components.Icon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: 16
                                source: "../icons/shield-lock.svg"
                                color: root.enrollAccent
                                iconSize: 28
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 14
                                text: root.enrollStagesTotal > 0 ? (root.enrollStagesCompleted + "/" + root.enrollStagesTotal) : "..."
                                color: Theme.fg
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                font.bold: true
                            }

                            Rectangle {
                                width: parent.width - 22
                                height: 3
                                radius: 1.5
                                color: root.enrollAccent
                                opacity: 0.85
                                x: 11
                                y: 16

                                SequentialAnimation on y {
                                    running: root.enrollmentActive
                                    loops: Animation.Infinite
                                    Components.Anim { from: 16; to: 69; duration: 1350; easing.type: Easing.InOutQuad }
                                    PauseAnimation { duration: 180 }
                                    Components.Anim { from: 69; to: 16; duration: 1350; easing.type: Easing.InOutQuad }
                                    PauseAnimation { duration: 180 }
                                }
                            }
                        }
                    }
                }

                Text {
                    text: root.enrollmentSummaryText()
                    color: root.enrollAccent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    horizontalAlignment: Text.AlignHCenter
                    Layout.fillWidth: true
                }

                Text {
                    text: root.actionStatus !== "" ? root.actionStatus : root.enrollmentGuidanceText()
                    color: root.enrollAccent
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Text {
                    text: root.enrollmentGuidanceText()
                    color: Theme.fg4
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeMini
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    Layout.fillWidth: true
                }

                Components.ActionButton {
                    text: "Cancel"
                    baseColor: Theme.bg
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: root.cancelRequested()
                }
            }
        }

        Rectangle {
            id: statusCard
            visible: root.statusText !== "" && !root.enrollmentActive
            Layout.fillWidth: true
            implicitHeight: statusLabel.implicitHeight + 28
            radius: Theme.popupRadius
            color: Qt.alpha(root.statusColor, 0.1)
            border.width: 1
            border.color: root.statusColor

            Text {
                id: statusLabel
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                text: root.statusText
                color: root.statusColor
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }
        }

        Text {
            text: "Choose a finger to add it. Click an enrolled finger to select it for removal."
            color: Theme.fg3
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSizeSmall
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }

        Components.SectionLabel { text: "FINGERS" }

        GridLayout {
            Layout.fillWidth: true
            columns: width >= Math.max(520, Theme.fontSize * 22) ? 2 : 1
            rowSpacing: 12
            columnSpacing: 12

            Repeater {
                model: root.handSections

                delegate: Rectangle {
                    id: sectionCard
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: sectionCol.implicitHeight + 28
                    radius: Theme.popupRadius
                    color: Theme.bg1
                    border.width: 1
                    border.color: Theme.bg3

                    ColumnLayout {
                        id: sectionCol
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10

                        Text {
                            text: sectionCard.modelData.title
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            Layout.fillWidth: true
                        }

                        Repeater {
                            model: sectionCard.modelData.fingers

                            delegate: Rectangle {
                                id: fingerCard
                                required property var modelData

                                readonly property string fingerKey: modelData.key
                                readonly property bool enrolled: root.isEnrolled(fingerKey)
                                readonly property bool selected: root.selectedEnrolledFinger === fingerKey
                                readonly property bool activeBusy: root.actionBusy && root.actionFinger === fingerKey
                                readonly property color stateAccent: activeBusy
                                    ? root.enrollAccent
                                    : (selected ? Theme.orangeBright : (enrolled ? Theme.greenBright : Theme.fg4))

                                Layout.fillWidth: true
                                implicitHeight: fingerRow.implicitHeight + 24
                                radius: Theme.btnRadius
                                color: activeBusy || selected
                                    ? Qt.alpha(stateAccent, 0.12)
                                    : (enrolled ? Qt.alpha(stateAccent, 0.1) : (fingerArea.containsMouse ? Theme.bg2 : Theme.bg))
                                border.width: 1
                                border.color: activeBusy || selected || enrolled ? stateAccent : Theme.bg3
                                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
                                Behavior on border.color { Components.StdCAnim { duration: Theme.animHover } }

                                RowLayout {
                                    id: fingerRow
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: Qt.alpha(fingerCard.stateAccent,
                                            fingerCard.activeBusy || fingerCard.selected || fingerCard.enrolled ? 0.18 : 0.12)

                                        Components.Icon {
                                            anchors.centerIn: parent
                                            source: fingerCard.enrolled ? "../icons/circle-check.svg" : "../icons/lock.svg"
                                            color: fingerCard.stateAccent
                                            iconSize: 16
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: fingerCard.modelData.label
                                            color: Theme.fg
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeSmall
                                            font.bold: true
                                            Layout.fillWidth: true
                                        }

                                        Text {
                                            text: root.fingerStatusText(fingerCard.fingerKey)
                                            color: fingerCard.stateAccent
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.fontSizeMini
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                Components.HoverLayer {
                                    id: fingerArea
                                    disabled: root.actionBusy || root.stateLoading
                                    flat: true
                                    onClicked: root.activateFinger(fingerCard.fingerKey)
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            id: removeCard
            visible: root.selectedEnrolledFinger !== "" && !root.actionBusy
            Layout.fillWidth: true
            implicitHeight: removeCol.implicitHeight + 28
            radius: Theme.popupRadius
            color: Qt.alpha(Theme.orangeBright, 0.1)
            border.width: 1
            border.color: Theme.orangeBright

            ColumnLayout {
                id: removeCol
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                Text {
                    text: "Remove " + root.fingerLabel(root.selectedEnrolledFinger) + "?"
                    color: Theme.fg
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                    font.bold: true
                    Layout.fillWidth: true
                }

                Text {
                    text: "This removes the saved fingerprint for that slot and keeps your other enrolled fingers intact."
                    color: Theme.fg3
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSizeSmall
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                RowLayout {
                    spacing: 8

                    Components.ActionButton {
                        text: "Remove"
                        baseColor: Theme.bg
                        hoverColor: Theme.redBright
                        borderColor: Theme.redBright
                        textColor: Theme.redBright
                        hoverTextColor: Theme.bg
                        fontBold: true
                        onClicked: {
                            let finger = root.selectedEnrolledFinger;
                            root.selectedEnrolledFinger = "";
                            root.deleteRequested(finger);
                        }
                    }

                    Components.ActionButton {
                        text: "Keep"
                        baseColor: Theme.bg
                        onClicked: root.selectedEnrolledFinger = ""
                    }
                }
            }
        }
    }
}
