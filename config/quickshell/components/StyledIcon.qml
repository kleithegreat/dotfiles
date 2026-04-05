import QtQuick
import QtQuick.Effects
import ".." as Root

Item {
    id: root

    property url source
    property color color: Root.Theme.fg
    property real iconSize: Root.Theme.iconSize
    property alias status: img.status

    property bool animate: false

    property string swapOpacityProperty: "opacity"
    property real swapOpacityOutFrom: root[root.swapOpacityProperty]
    property real swapOpacityOutTo: 0.0
    property int swapOpacityOutDuration: Root.Theme.animContentSwap
    property int swapOpacityOutEasing: Easing.InQuad
    property real swapOpacityInFrom: root.swapOpacityOutTo
    property real swapOpacityInTo: 1.0
    property int swapOpacityInDuration: Root.Theme.animContentSwap
    property int swapOpacityInEasing: Easing.OutCubic

    property string swapScaleProperty: "scale"
    property real swapScaleOutFrom: root[root.swapScaleProperty]
    property real swapScaleOutTo: 0.6
    property int swapScaleOutDuration: Root.Theme.animContentSwap
    property int swapScaleOutEasing: Easing.InQuad
    property real swapScaleInFrom: root.swapScaleOutTo
    property real swapScaleInTo: 1.0
    property int swapScaleInDuration: Root.Theme.animNormal
    property int swapScaleInEasing: Easing.OutCubic

    implicitWidth: iconSize
    implicitHeight: iconSize

    Image {
        id: img
        anchors.fill: parent
        source: root.source
        sourceSize: Qt.size(root.width * 2, root.height * 2)
        visible: false
        fillMode: Image.PreserveAspectFit
    }

    MultiEffect {
        anchors.fill: img
        source: img
        brightness: 1.0
        colorization: 1.0
        colorizationColor: root.color
    }

    Behavior on source {
        enabled: root.animate

        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: root
                    property: root.swapOpacityProperty
                    from: root.swapOpacityOutFrom
                    to: root.swapOpacityOutTo
                    duration: root.swapOpacityOutDuration
                    easing.type: root.swapOpacityOutEasing
                }

                Anim {
                    target: root
                    property: root.swapScaleProperty
                    from: root.swapScaleOutFrom
                    to: root.swapScaleOutTo
                    duration: root.swapScaleOutDuration
                    easing.type: root.swapScaleOutEasing
                }
            }

            PropertyAction {
                target: root
                property: "source"
            }

            ParallelAnimation {
                Anim {
                    target: root
                    property: root.swapOpacityProperty
                    from: root.swapOpacityInFrom
                    to: root.swapOpacityInTo
                    duration: root.swapOpacityInDuration
                    easing.type: root.swapOpacityInEasing
                }

                Anim {
                    target: root
                    property: root.swapScaleProperty
                    from: root.swapScaleInFrom
                    to: root.swapScaleInTo
                    duration: root.swapScaleInDuration
                    easing.type: root.swapScaleInEasing
                }
            }
        }
    }
}
