import QtQuick
import qs

NumberAnimation {
    duration: Motion.quick
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Motion.standard
}
