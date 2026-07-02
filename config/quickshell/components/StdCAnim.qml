import QtQuick
import ".." as Root

// CAnim preset for the shared standard curve (Theme.animCurveStandard).
CAnim {
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Root.Theme.animCurveStandard
}
