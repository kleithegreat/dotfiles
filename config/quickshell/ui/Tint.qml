import QtQuick
import qs

ColorAnimation {
    duration: Motion.instant
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Motion.standard
}
