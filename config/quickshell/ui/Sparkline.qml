import QtQuick
import qs

// Recent history for one measurement. A number tells you where you are; this
// tells you whether it is holding steady, which is the question a diagnostic is
// usually being asked.
Item {
    id: root

    property var samples: []
    property color stroke: Theme.accent
    property bool lowerIsBetter: true

    implicitWidth: 84
    implicitHeight: 22
    visible: samples.length > 1

    onSamplesChanged: plot.requestPaint()
    onStrokeChanged: plot.requestPaint()

    Canvas {
        id: plot
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();

            const points = root.samples;
            if (points.length < 2)
                return;

            let low = points[0];
            let high = points[0];
            for (let i = 1; i < points.length; i++) {
                low = Math.min(low, points[i]);
                high = Math.max(high, points[i]);
            }
            // A flat series should read as flat and sit in the middle, not get
            // amplified into noise or pinned to the top of the box.
            const flat = high - low < 0.0001;
            const spread = flat ? 1 : high - low;
            const pad = 2;
            const usableHeight = height - pad * 2;

            const at = i => ({
                x: (i / (points.length - 1)) * width,
                y: flat ? height / 2 : pad + usableHeight - ((points[i] - low) / spread) * usableHeight
            });

            ctx.beginPath();
            ctx.moveTo(0, height);
            for (let i = 0; i < points.length; i++) {
                const p = at(i);
                ctx.lineTo(p.x, p.y);
            }
            ctx.lineTo(width, height);
            ctx.closePath();
            ctx.fillStyle = Qt.rgba(root.stroke.r, root.stroke.g, root.stroke.b, 0.14);
            ctx.fill();

            ctx.beginPath();
            for (let i = 0; i < points.length; i++) {
                const p = at(i);
                if (i === 0)
                    ctx.moveTo(p.x, p.y);
                else
                    ctx.lineTo(p.x, p.y);
            }
            ctx.strokeStyle = root.stroke;
            ctx.lineWidth = 1.5;
            ctx.lineJoin = "round";
            ctx.lineCap = "round";
            ctx.stroke();
        }
    }
}
