import QtQuick
import qs

// Overflow must show: the edges fade, and the ordinary wheel scrolls it sideways.
Item {
    id: root

    property var options: []
    property string current: ""
    property bool showsMissing: false
    property color fadeColor: Theme.raised

    signal picked(string value)

    onOptionsChanged: {
        pill.placed = false;
        pill.target = null;
    }

    implicitHeight: Metrics.controlHeight
    implicitWidth: row.implicitWidth

    readonly property bool overflowing: strip.contentWidth > strip.width + 1

    Flickable {
        id: strip

        anchors.fill: parent
        contentWidth: row.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.DragAndOvershootBounds
        pixelAligned: true
        clip: true

        Rectangle {
            id: pill

            // Set by the option that becomes chosen.
            property Item target: null
            // The first placement lands; only moves after it travel.
            property bool placed: false

            onTargetChanged: {
                if (target)
                    Qt.callLater(() => pill.placed = true);
            }

            visible: target !== null && target.chosen
            x: target ? target.x : 0
            y: target ? target.y : 0
            width: target ? target.width : 0
            height: target ? target.height : 0
            radius: Metrics.rControl
            color: Theme.fillActive

            Behavior on x {
                enabled: pill.placed

                Anim {
                    duration: Motion.settled
                    easing.bezierCurve: Motion.spring
                }
            }
            Behavior on width {
                enabled: pill.placed

                Anim {
                    duration: Motion.settled
                    easing.bezierCurve: Motion.spring
                }
            }
        }

        Row {
            id: row
            height: parent.height
            spacing: Metrics.s1

            Repeater {
                model: root.options

                Pressable {
                    id: option

                    required property var modelData
                    readonly property string value: modelData.value !== undefined ? modelData.value : modelData
                    readonly property string label: modelData.label !== undefined ? modelData.label : modelData
                    readonly property bool missing: root.showsMissing && !Catalog.available(option.value)
                    readonly property bool chosen: root.current === option.value

                    onChosenChanged: {
                        if (chosen)
                            pill.target = option;
                    }
                    Component.onCompleted: {
                        if (chosen)
                            pill.target = option;
                    }

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: caption.implicitWidth + Metrics.s3 * 2
                    implicitHeight: Metrics.controlHeight
                    opacity: option.missing ? 0.4 : 1
                    onClicked: root.picked(option.value)

                    Label {
                        id: caption
                        anchors.centerIn: parent
                        text: option.label
                        role: "callout"
                        font.weight: option.chosen ? Theme.weightMedium : Theme.weightRegular
                        color: option.chosen ? Theme.text : Theme.textSecondary
                    }
                }
            }
        }
    }

    WheelGlide {
        id: wheel
        flick: strip
        horizontal: true
        active: root.overflowing
    }

    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2
        radius: 1
        color: Theme.fillTrack
        visible: root.overflowing
        opacity: strip.moving || wheel.running ? 1 : 0.55

        Behavior on opacity {
            Anim {}
        }

        Rectangle {
            height: parent.height
            radius: parent.radius
            color: Theme.textQuaternary
            width: Math.max(24, parent.width * (strip.width / Math.max(1, strip.contentWidth)))
            x: (parent.width - width) * Math.max(0, Math.min(1, strip.contentX / Math.max(1, strip.contentWidth - strip.width)))
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Metrics.s8
        visible: strip.contentX > 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root.fadeColor }
            GradientStop { position: 1.0; color: Theme.withAlpha(root.fadeColor, 0) }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Metrics.s8
        visible: strip.contentX < strip.contentWidth - strip.width - 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Theme.withAlpha(root.fadeColor, 0) }
            GradientStop { position: 1.0; color: root.fadeColor }
        }
    }
}
