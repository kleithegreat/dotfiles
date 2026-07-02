import qs
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../components" as Components

FocusScope {
    id: mprisPop
    property bool active: false; signal close()
    property bool closing: false
    readonly property bool hasPlayers: Mpris.players.values.length > 0
    readonly property bool overlayVisible: (active || closing) && hasPlayers
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    property var player: {
        let players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying) return players[i];
        }
        for (let i = 0; i < players.length; i++) {
            if (players[i].trackTitle) return players[i];
        }
        return null;
    }
    property real pos: player?.position ?? 0
    property real len: player?.length ?? 0
    property bool hasLen: len > 0

    // Track art cross-fade state
    property string currentArtUrl: player?.trackArtUrl ?? ""
    property string prevArtUrl: ""
    Component.onCompleted: prevArtUrl = currentArtUrl

    onCurrentArtUrlChanged: {
        if (prevArtUrl !== currentArtUrl) {
            artImgOld.source = prevArtUrl;
            artCrossfade.start();
        }
        prevArtUrl = currentArtUrl;
    }

    Timer {
        interval: 500; running: mprisPop.active && (player?.isPlaying ?? false); repeat: true
        // position is computed on demand; emitting its notify signal re-evaluates
        // the pos binding without destroying it (paused seeks/track changes still work).
        onTriggered: mprisPop.player?.positionChanged()
    }

    function fmtTime(seconds) {
        let s = Math.floor(seconds);
        let m = Math.floor(s / 60); s = s % 60;
        return m + ":" + s.toString().padStart(2, '0');
    }

    onActiveChanged: {
        if (active) {
            if (!hasPlayers) {
                close();
                return;
            }
            mprisCloseAnim.stop();
            closing = false;
            forceActiveFocus();
            mprisPanel.opacity = 0;
            mprisPanel.scale = Theme.popupStartScale;
            mprisOpenAnim.restart();
        }
        else if (!closing) { mprisOpenAnim.stop(); closing = true; mprisCloseAnim.restart(); }
    }
    onHasPlayersChanged: {
        if (!hasPlayers && active)
            close();
    }
    Keys.onEscapePressed: mprisPop.close()

    component MediaButton: Rectangle {
        id: mediaButton
        required property real size
        required property string icon
        required property int iconSize
        required property color idleColor
        required property color hoverColor
        signal clicked()

        width: size
        height: size
        radius: Theme.hoverRadius
        color: "transparent"

        Components.HoverLayer {
            id: mediaButtonHover
            pressedScale: 0.85
            onClicked: mediaButton.clicked()

            Components.Icon {
                anchors.centerIn: parent
                source: mediaButton.icon
                iconSize: mediaButton.iconSize
                color: mediaButtonHover.containsMouse ? mediaButton.hoverColor : mediaButton.idleColor
                Behavior on color { Components.StdCAnim { duration: Theme.animHover } }
            }
        }
    }

    SequentialAnimation {
        id: mprisOpenAnim
        ParallelAnimation {
            Components.Anim {
                target: mprisPanel
                property: "opacity"
                to: 1
                duration: Theme.animPopupIn
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveEmphasizedEnter
            }
            SequentialAnimation {
                PauseAnimation { duration: Theme.animPopupScaleLead }
                Components.Anim {
                    target: mprisPanel
                    property: "scale"
                    to: 1.0
                    duration: Math.max(0, Theme.animPopupIn - Theme.animPopupScaleLead)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Theme.animCurveEmphasizedEnter
                }
            }
        }
    }
    SequentialAnimation {
        id: mprisCloseAnim
        ParallelAnimation {
            Components.Anim {
                target: mprisPanel
                property: "opacity"
                to: 0
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
            Components.Anim {
                target: mprisPanel
                property: "scale"
                to: Theme.popupStartScale
                duration: Theme.animPopupOut
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Theme.animCurveExit
            }
        }
        ScriptAction { script: { mprisPop.closing = false; } }
    }

    Rectangle {
        id: mprisPanel
        anchors.left: parent.left; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.leftMargin: Theme.gapOut
        width: Theme.mprisPopupWidth; height: mprisCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        opacity: 0; scale: Theme.popupStartScale
        transformOrigin: Item.TopLeft
        layer.enabled: mprisOpenAnim.running || mprisCloseAnim.running
        layer.smooth: true
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: mprisCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: Theme.sectionSpacing

            // Art + Info
            RowLayout { spacing: 12
                Rectangle {
                    width: Theme.mprisArtSize * 2; height: Theme.mprisArtSize * 2; radius: 8; color: Theme.bg2; clip: true

                    // Old art for cross-fade
                    Image {
                        id: artImgOld; anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop; smooth: true
                        opacity: 0; visible: opacity > 0
                    }

                    Image {
                        id: artImg; anchors.fill: parent
                        source: mprisPop.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop; smooth: true
                        visible: status === Image.Ready
                    }

                    // Cross-fade animation
                    SequentialAnimation {
                        id: artCrossfade
                        PropertyAction { target: artImgOld; property: "opacity"; value: 1 }
                        PropertyAction { target: artImg; property: "opacity"; value: 0 }
                        ParallelAnimation {
                            Components.Anim {
                                target: artImgOld
                                property: "opacity"
                                to: 0
                                duration: Theme.animContentSwap
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveExit
                            }
                            Components.Anim {
                                target: artImg
                                property: "opacity"
                                to: 1
                                duration: Theme.animContentSwap
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveStandard
                            }
                        }
                    }

                    Components.Icon {
                        anchors.centerIn: parent; visible: artImg.status !== Image.Ready && artImgOld.opacity === 0
                        source: "../icons/album.svg"; color: Theme.fg4; iconSize: 32
                    }
                }
                Item {
                    id: trackInfoContainer
                    Layout.fillWidth: true
                    implicitHeight: trackInfoCol.implicitHeight
                    clip: true

                    property string _lastTitle: ""

                    ColumnLayout {
                        id: trackInfoCol; width: parent.width; spacing: 4
                        Text {
                            text: mprisPop.player?.trackTitle ?? ""; color: Theme.fg
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        Text {
                            text: mprisPop.player?.trackArtist ?? ""; color: Theme.fg3
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== ""
                        }
                        Text {
                            text: mprisPop.player?.trackAlbum ?? ""; color: Theme.fg4
                            font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== ""
                        }
                    }

                    Connections {
                        target: mprisPop.player ?? null
                        function onTrackTitleChanged() {
                            let t = mprisPop.player?.trackTitle ?? "";
                            if (t !== trackInfoContainer._lastTitle && trackInfoContainer._lastTitle !== "") {
                                trackChangeAnim.start();
                            }
                            trackInfoContainer._lastTitle = t;
                        }
                    }

                    SequentialAnimation {
                        id: trackChangeAnim
                        ParallelAnimation {
                            Components.Anim {
                                target: trackInfoCol
                                property: "opacity"
                                to: 0
                                duration: Theme.animContentSwap / 2
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveExit
                            }
                            Components.Anim {
                                target: trackInfoCol
                                property: "y"
                                to: -6
                                duration: Theme.animContentSwap / 2
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveExit
                            }
                        }
                        ScriptAction { script: { trackInfoCol.y = 6; } }
                        ParallelAnimation {
                            Components.Anim {
                                target: trackInfoCol
                                property: "opacity"
                                to: 1
                                duration: Theme.animContentSwap / 2
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveStandard
                            }
                            Components.Anim {
                                target: trackInfoCol
                                property: "y"
                                to: 0
                                duration: Theme.animContentSwap / 2
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveStandard
                            }
                        }
                    }
                }
            }

            // Seek bar
            ColumnLayout { spacing: 4; visible: mprisPop.hasLen; Layout.fillWidth: true
                Rectangle {
                    Layout.fillWidth: true; height: 4; radius: 2; color: Theme.bg3
                    Rectangle {
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        width: mprisPop.hasLen ? parent.width * Math.min(1.0, mprisPop.pos / mprisPop.len) : 0
                        radius: 2; color: Theme.greenBright
                        Behavior on width {
                            Components.Anim {
                                duration: Theme.animMedium
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Theme.animCurveStandard
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (mprisPop.player?.canSeek && mprisPop.hasLen)
                                mprisPop.player.position = (mouse.x / parent.width) * mprisPop.len;
                        }
                    }
                }
                RowLayout { Layout.fillWidth: true
                    Text { text: mprisPop.fmtTime(mprisPop.pos); color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini }
                    Item { Layout.fillWidth: true }
                    Text { text: mprisPop.fmtTime(mprisPop.len); color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeMini }
                }
            }

            // Controls
            RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 24
                MediaButton {
                    size: 28
                    icon: "../icons/player-prev.svg"
                    iconSize: 18
                    idleColor: Theme.fg3
                    hoverColor: Theme.fg
                    onClicked: { if (mprisPop.player?.canGoPrevious) mprisPop.player.previous(); }
                }
                MediaButton {
                    size: 32
                    icon: (mprisPop.player?.isPlaying ?? false) ? "../icons/player-pause.svg" : "../icons/player-play.svg"
                    iconSize: 22
                    idleColor: Theme.fg
                    hoverColor: Theme.yellowBright
                    onClicked: { if (mprisPop.player?.canTogglePlaying) mprisPop.player.isPlaying = !mprisPop.player.isPlaying; }
                }
                MediaButton {
                    size: 28
                    icon: "../icons/player-next.svg"
                    iconSize: 18
                    idleColor: Theme.fg3
                    hoverColor: Theme.fg
                    onClicked: { if (mprisPop.player?.canGoNext) mprisPop.player.next(); }
                }
            }
        }
    }
}
