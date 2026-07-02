import QtQuick
import ".." as Root

Text {
    id: root

    property bool animate: false

    renderType: Text.NativeRendering
    font.family: Root.Theme.fontFamily
    font.pixelSize: Root.Theme.fontSize
    color: Root.Theme.fg

    Behavior on text {
        enabled: root.animate

        ContentSwapAnim {
            target: root
            swapProperty: "text"
        }
    }
}
