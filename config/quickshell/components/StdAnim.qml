import QtQuick
import ".." as Root

// Anim preset for the shared standard curve (Theme.animCurveStandard).
Anim {
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Root.Theme.animCurveStandard
}
