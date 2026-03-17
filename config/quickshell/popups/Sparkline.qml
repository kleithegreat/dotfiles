import QtQuick

Canvas {
    id: spark
    property var values: []
    property color lineColor: Theme.greenBright
    property real lineWidth: 1.5

    implicitWidth: 100; implicitHeight: 18

    onValuesChanged: requestPaint()
    onLineColorChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        ctx.clearRect(0, 0, width, height);
        if (values.length < 2) return;

        var vals = values;
        var min = vals[0], max = vals[0];
        for (var k = 1; k < vals.length; k++) {
            if (vals[k] < min) min = vals[k];
            if (vals[k] > max) max = vals[k];
        }
        var range = max - min;
        if (range < 0.001) range = 1;

        var pad = 2;
        var h = height - pad * 2;
        var step = width / (vals.length - 1);

        ctx.beginPath();
        ctx.strokeStyle = Qt.rgba(lineColor.r, lineColor.g, lineColor.b, lineColor.a);
        ctx.lineWidth = lineWidth;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";

        for (var i = 0; i < vals.length; i++) {
            var x = i * step;
            var y = pad + h - ((vals[i] - min) / range) * h;
            if (i === 0) ctx.moveTo(x, y);
            else ctx.lineTo(x, y);
        }
        ctx.stroke();
    }
}
