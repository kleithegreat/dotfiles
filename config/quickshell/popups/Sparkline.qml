import QtQuick

Canvas {
    id: root

    property var values: []
    property color lineColor: Theme.greenBright

    implicitWidth: 100
    implicitHeight: 18

    onValuesChanged: requestPaint()
    onLineColorChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.clearRect(0, 0, width, height);

        if (values.length < 2) return;

        let min = values[0], max = values[0];
        for (let i = 1; i < values.length; i++) {
            if (values[i] < min) min = values[i];
            if (values[i] > max) max = values[i];
        }

        const range = max - min || 1;
        const stepX = width / (values.length - 1);

        ctx.beginPath();
        ctx.moveTo(0, height - (values[0] - min) / range * height);
        for (let i = 1; i < values.length; i++) {
            ctx.lineTo(i * stepX, height - (values[i] - min) / range * height);
        }

        ctx.strokeStyle = root.lineColor;
        ctx.lineWidth = 1.5;
        ctx.lineJoin = "round";
        ctx.lineCap = "round";
        ctx.stroke();
    }
}
