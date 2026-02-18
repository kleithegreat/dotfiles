import qs
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

PanelWindow {
    id: mprisPop
    property bool active: false; signal close()
    visible: active && Mpris.players.values.length > 0
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "quickshell:mpris"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    property var player: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    property real pos: player?.position ?? 0
    property real len: player?.length ?? 0
    property bool hasLen: len > 0

    Timer {
        interval: 500; running: mprisPop.active && (player?.isPlaying ?? false); repeat: true
        onTriggered: mprisPop.pos = player?.position ?? 0
    }

    function fmtTime(us) {
        let s = Math.floor(us / 1000000);
        let m = Math.floor(s / 60); s = s % 60;
        return m + ":" + s.toString().padStart(2, '0');
    }

    Rectangle {
        anchors.fill: parent; color: "transparent"; focus: true
        Keys.onEscapePressed: mprisPop.close()
        MouseArea { anchors.fill: parent; onClicked: mprisPop.close() }
    }

    Rectangle {
        anchors.left: parent.left; anchors.top: parent.top
        anchors.topMargin: Theme.popupTopMargin; anchors.leftMargin: Theme.gapOut + Theme.barPadding
        width: Theme.mprisPopupWidth; height: mprisCol.implicitHeight + Theme.popupPadding * 2
        radius: Theme.popupRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: mprisCol; anchors.fill: parent; anchors.margins: Theme.popupPadding; spacing: 12

            // Art + Info
            RowLayout { spacing: 12
                Rectangle {
                    width: Theme.mprisArtSize; height: Theme.mprisArtSize; radius: 8; color: Theme.bg2; clip: true
                    Image {
                        id: artImg; anchors.fill: parent
                        source: mprisPop.player?.trackArtUrl ?? ""
                        fillMode: Image.PreserveAspectCrop; smooth: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent; visible: artImg.status !== Image.Ready
                        text: "󰀥"; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: 32
                    }
                }
                ColumnLayout { spacing: 4; Layout.fillWidth: true
                    Text { text: mprisPop.player?.trackTitle ?? "Unknown"; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; elide: Text.ElideRight; Layout.fillWidth: true }
                    Text { text: mprisPop.player?.trackArtist ?? ""; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                    Text { text: mprisPop.player?.trackAlbum ?? ""; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
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
                        Behavior on width { NumberAnimation { duration: 300 } }
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
                    Text { text: mprisPop.fmtTime(mprisPop.pos); color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                    Item { Layout.fillWidth: true }
                    Text { text: mprisPop.fmtTime(mprisPop.len); color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall - 1 }
                }
            }

            // Controls
            RowLayout { Layout.alignment: Qt.AlignHCenter; spacing: 24
                Text {
                    text: "󰒮"; color: pA.containsMouse ? Theme.fg : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 18
                    MouseArea { id: pA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { if (mprisPop.player?.canGoPrevious) mprisPop.player.previous(); } }
                }
                Text {
                    text: (mprisPop.player?.isPlaying ?? false) ? "󰏤" : "󰐊"
                    color: ppA.containsMouse ? Theme.yellowBright : Theme.fg
                    font.family: Theme.fontFamily; font.pixelSize: 22
                    MouseArea { id: ppA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { if (mprisPop.player?.canTogglePlaying ?? false) mprisPop.player.isPlaying = !mprisPop.player.isPlaying; } }
                }
                Text {
                    text: "󰒭"; color: nA.containsMouse ? Theme.fg : Theme.fg3
                    font.family: Theme.fontFamily; font.pixelSize: 18
                    MouseArea { id: nA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true
                        onClicked: { if (mprisPop.player?.canGoNext) mprisPop.player.next(); } }
                }
            }
        }
    }
}
