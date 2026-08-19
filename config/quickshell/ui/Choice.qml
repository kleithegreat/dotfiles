import QtQuick
import qs

// A bounded set of options, laid out as a row that scrolls when it does not
// fit. It stays a row rather than becoming a dropdown because the options are
// the answer to the question next to them — hiding four of them behind a click
// is a menu built for a list that does not exist. When it does overflow it has
// to *say so*: the edges fade into the card, and the ordinary wheel scrolls it
// sideways, because a horizontal list that only answers to a horizontal wheel
// is a list most people cannot reach the end of.
Item {
    id: root

    property var options: []
    property string current: ""
    property bool showsMissing: false
    // What the fade resolves to; overridden when a Choice sits on glass.
    property color ground: Theme.raised

    signal picked(string value)

    implicitHeight: Metrics.controlHeight
    implicitWidth: row.implicitWidth

    readonly property bool overflowing: strip.contentWidth > strip.width + 1

    Flickable {
        id: strip

        anchors.fill: parent
        contentWidth: row.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        pixelAligned: true
        clip: true

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

                    anchors.verticalCenter: parent.verticalCenter
                    implicitWidth: caption.implicitWidth + Metrics.s3 * 2
                    implicitHeight: Metrics.controlHeight
                    radius: Metrics.rControl
                    active: root.current === option.value
                    opacity: option.missing ? 0.4 : 1
                    onClicked: root.picked(option.value)

                    Label {
                        id: caption
                        anchors.centerIn: parent
                        text: option.label
                        role: "callout"
                        font.weight: root.current === option.value ? Theme.weightMedium : Theme.weightRegular
                        color: root.current === option.value ? Theme.text : Theme.textSecondary
                    }
                }
            }
        }
    }

    // Both wheels move it: the vertical one because that is the wheel most
    // people have under a finger, the horizontal one because the mice that
    // have it expect it to work.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        enabled: root.overflowing
        onWheel: event => {
            const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y;
            glide.to = Math.max(0, Math.min(strip.contentWidth - strip.width, (glide.running ? glide.to : strip.contentX) - delta / 120 * Metrics.wheelStep));
            glide.restart();
        }
    }

    NumberAnimation {
        id: glide
        target: strip
        property: "contentX"
        duration: Motion.quick
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.enter
    }

    // A rail under the options, sized to the visible fraction. The fades say
    // "there is more"; this says how much more.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: 2
        radius: 1
        color: Theme.fillTrack
        visible: root.overflowing
        opacity: strip.moving || glide.running ? 1 : 0.55

        Behavior on opacity {
            Anim {
                duration: Motion.quick
            }
        }

        Rectangle {
            height: parent.height
            radius: parent.radius
            color: Theme.textQuaternary
            width: Math.max(24, parent.width * (strip.width / Math.max(1, strip.contentWidth)))
            x: (parent.width - width) * (strip.contentX / Math.max(1, strip.contentWidth - strip.width))
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
            GradientStop { position: 0.0; color: root.ground }
            GradientStop { position: 1.0; color: Theme.withAlpha(root.ground, 0) }
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
            GradientStop { position: 0.0; color: Theme.withAlpha(root.ground, 0) }
            GradientStop { position: 1.0; color: root.ground }
        }
    }
}
