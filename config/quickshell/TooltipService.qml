pragma Singleton
import QtQuick

QtObject {
    id: root

    property string text: ""
    property real targetX: 0
    property real targetY: 0
    property bool visible: false

    property bool _warm: false

    function show(text, globalX, globalY) {
        root.text = text;
        root.targetX = globalX;
        root.targetY = globalY;

        if (_warm) {
            _lingerTimer.stop();
            _showTimer.stop();
            root.visible = true;
        } else {
            _lingerTimer.stop();
            _showTimer.restart();
        }
    }

    function hide() {
        _showTimer.stop();
        if (root.visible) {
            _lingerTimer.restart();
        } else {
            root._warm = false;
        }
    }

    property Timer _showTimer: Timer {
        interval: 300
        onTriggered: {
            root.visible = true;
            root._warm = true;
        }
    }

    property Timer _lingerTimer: Timer {
        interval: 150
        onTriggered: {
            root.visible = false;
            root._warm = false;
        }
    }
}
