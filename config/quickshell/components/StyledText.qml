import QtQuick
import ".." as Root

Text {
    id: root

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

    renderType: Text.NativeRendering
    font.family: Root.Theme.fontFamily
    font.pixelSize: Root.Theme.fontSize
    color: Root.Theme.fg

    Behavior on text {
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

            // Swap the visible string only after the element has faded/scaled out.
            PropertyAction {
                target: root
                property: "text"
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
