import QtQuick
import ".." as Root

// Fade/scale-out, swap, fade/scale-in animation for content-change Behaviors
// (see StyledText and StyledIcon). `swapProperty` names the property whose
// pending value is applied between the two phases.
SequentialAnimation {
    id: root

    required property Item target
    required property string swapProperty

    ParallelAnimation {
        Anim {
            target: root.target
            property: "opacity"
            from: root.target.opacity
            to: 0.0
            duration: Root.Theme.animContentSwap
            easing.type: Easing.InQuad
        }

        Anim {
            target: root.target
            property: "scale"
            from: root.target.scale
            to: 0.6
            duration: Root.Theme.animContentSwap
            easing.type: Easing.InQuad
        }
    }

    // Swap the visible content only after the element has faded/scaled out.
    PropertyAction {
        target: root.target
        property: root.swapProperty
    }

    ParallelAnimation {
        Anim {
            target: root.target
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: Root.Theme.animContentSwap
        }

        Anim {
            target: root.target
            property: "scale"
            from: 0.6
            to: 1.0
        }
    }
}
