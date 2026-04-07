import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris
import "../components" as Components

FocusScope {
    id: mprisPop
    property bool active: false; signal close()
    property bool closing: false
    readonly property bool overlayVisible: (active || closing) && Mpris.players.values.length > 0
    readonly property Item panelItem: mprisPanel
    readonly property Item focusTarget: mprisPop
    readonly property bool scrimEnabled: false
    readonly property color scrimColor: "transparent"
    readonly property real scrimOpacity: 0
    visible: overlayVisible
    anchors.fill: parent
    focus: active
    Keys.priority: Keys.BeforeItem

    /*
    Legacy per-popup PanelWindow wrapper retained during the overlay-host migration:
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:mpris"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: mprisPop.close()
        MouseArea { anchors.fill: parent; onClicked: mprisPop.close() }
    }
    */

    property var player: {
        let players = Mpris.players.values;
        for (let i = 0; i < players.length; i++) {
            if (players[i].isPlaying) return players[i];
        }
        return players.length > 0 ? players[0] : null;
    }
    property real pos: player?.position ?? 0
    property real len: player?.length ?? 0
    property bool hasLen: len > 0

    // Track art cross-fade state
    property string currentArtUrl: player?.trackArtUrl ?? ""
    property string prevArtUrl: ""

    onCurrentArtUrlChanged: {
        if (prevArtUrl !== currentArtUrl) {
            prevArtUrl = artImg.source;
            artImgOld.source = prevArtUrl;
            artCrossfade.start();
        }
    }

    Timer {
        interval: 500; running: mprisPop.active && (player?.isPlaying ?? false); repeat: true
        onTriggered: mprisPop.pos = player?.position ?? 0
    }

    function fmtTime(us) {
        let s = Math.floor(us / 1000000);
        let m = Math.floor(s / 60); s = s % 60;
        return m + ":" + s.toString().padStart(2, '0');
    }

    onActiveChanged: {
        if (active) {
            forceActiveFocus();
            mprisPanel.opacity = 0;
            mprisPanel.scale = 0.92;
            mprisOpenAnim.start();
        }
        else if (!closing) { closing = true; mprisCloseAnim.start(); }
    }
    Keys.onEscapePressed: mprisPop.close()

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
                PauseAnimation { duration: 40 }
                Components.Anim {
                    target: mprisPanel
                    property: "scale"
                    to: 1.0
                    duration: Theme.animPopupIn - 40
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
                to: 0.92
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
        opacity: 0; scale: 0.92
        transformOrigin: Item.TopLeft
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
                        NumberAnimation { target: artImgOld; property: "opacity"; to: 1; duration: 0 }
                        NumberAnimation { target: artImg; property: "opacity"; to: 0; duration: 0 }
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
                            text: mprisPop.player?.trackTitle ?? "Unknown"; color: Theme.fg
                            font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize; font.bold: true
                            elide: Text.ElideRight; Layout.fillWidth: true
                        }
                        Text {
                            text: mprisPop.player?.trackArtist ?? ""; color: Theme.fg3
                            font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== ""
                        }
                        Text {
                            text: mprisPop.player?.trackAlbum ?? ""; color: Theme.fg4
                            font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall
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
                                duration: 300
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
                    Text { text: mprisPop.fmtTime(mprisPop.pos); color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                    Item { Layout.fillWidth: true }
                    Text { text: mprisPop.fmtTime(mprisPop.len); color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                }
            }

            // Controls
            RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 24
                // Previous
                Rectangle {
                    width: 28; height: 28; radius: Theme.hoverRadius; color: "transparent"
                    Components.HoverLayer {
                        id: pA
                        color: Theme.bg2
                        hoverOpacity: 0.6
                        pressedOpacity: 0.9
                        pressedScale: 0.85
                        onClicked: { if (mprisPop.player?.canGoPrevious) mprisPop.player.previous(); }

                        Components.Icon {
                            anchors.centerIn: parent; source: "../icons/player-prev.svg"
                            color: pA.containsMouse ? Theme.fg : Theme.fg3
                            Behavior on color {
                                Components.CAnim {
                                    duration: Theme.animHover
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                            iconSize: 18
                        }
                    }
                }
                // Play/Pause
                Rectangle {
                    width: 32; height: 32; radius: Theme.hoverRadius; color: "transparent"
                    Components.HoverLayer {
                        id: ppA
                        color: Theme.bg2
                        hoverOpacity: 0.6
                        pressedOpacity: 0.9
                        pressedScale: 0.85
                        onClicked: { if (mprisPop.player?.canTogglePlaying ?? false) mprisPop.player.isPlaying = !mprisPop.player.isPlaying; }

                        Components.Icon {
                            anchors.centerIn: parent
                            source: (mprisPop.player?.isPlaying ?? false) ? "../icons/player-pause.svg" : "../icons/player-play.svg"
                            color: ppA.containsMouse ? Theme.yellowBright : Theme.fg
                            Behavior on color {
                                Components.CAnim {
                                    duration: Theme.animHover
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                            iconSize: 22
                        }
                    }
                }
                // Next
                Rectangle {
                    width: 28; height: 28; radius: Theme.hoverRadius; color: "transparent"
                    Components.HoverLayer {
                        id: nA
                        color: Theme.bg2
                        hoverOpacity: 0.6
                        pressedOpacity: 0.9
                        pressedScale: 0.85
                        onClicked: { if (mprisPop.player?.canGoNext) mprisPop.player.next(); }

                        Components.Icon {
                            anchors.centerIn: parent; source: "../icons/player-next.svg"
                            color: nA.containsMouse ? Theme.fg : Theme.fg3
                            Behavior on color {
                                Components.CAnim {
                                    duration: Theme.animHover
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Theme.animCurveStandard
                                }
                            }
                            iconSize: 18
                        }
                    }
                }
            }
        }
    }
}
