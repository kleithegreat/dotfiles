import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.bar as Bar

Scope {
    id: root

    Variants {
        model: Quickshell.screens

        Bar.Bar {
            required property var modelData
            screen: modelData
        }
    }

    // ══════════════════════════════════════════════
    // ── Notification Server (must be at root level)
    // ══════════════════════════════════════════════
    NotificationServer {
        id: server
        bodySupported: true
        bodyImagesSupported: true
        imageSupported: true
        keepOnReload: false

        onNotification: (notification) => {
            let data = {
                appName: notification.appName || "Notification",
                summary: notification.summary || "",
                body: notification.body || "",
                nid: notification.id
            };
            notifModel.insert(0, data);

            let timeout = notification.expireTimeout > 0
                ? notification.expireTimeout
                : Theme.notifTimeout;

            dismissTimer.createObject(root, {
                targetNid: data.nid,
                interval: timeout
            });
        }
    }

    Component {
        id: dismissTimer
        Timer {
            required property int targetNid
            running: true
            repeat: false
            onTriggered: {
                root.removeNotification(targetNid);
                this.destroy();
            }
        }
    }

    ListModel {
        id: notifModel
    }

    function removeNotification(nid) {
        for (let i = 0; i < notifModel.count; i++) {
            if (notifModel.get(i).nid === nid) {
                notifModel.remove(i);
                break;
            }
        }
    }

    // ── Notification Popup Window ──
    PanelWindow {
        id: popupWindow

        anchors {
            top: true
            right: true
        }

        margins {
            top: Theme.barHeight + Theme.barMargin + Theme.gapOut;
            right: Theme.gapOut
        }

        implicitWidth: Theme.notifWidth
        implicitHeight: notifColumn.implicitHeight
        visible: notifModel.count > 0
        color: "transparent"

        WlrLayershell.namespace: "quickshell:notifications"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore

        Column {
            id: notifColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 0
            spacing: Theme.notifSpacing

            Repeater {
                model: notifModel

                Rectangle {
                    id: card
                    required property string appName
                    required property string summary
                    required property string body
                    required property int nid
                    required property int index

                    width: Theme.notifWidth
                    height: cardContent.implicitHeight + Theme.notifPadding * 2
                    radius: Theme.notifRadius
                    color: Theme.bg1
                    border.width: 1
                    border.color: Theme.bg3

                    opacity: 0
                    x: 20
                    Component.onCompleted: {
                        opacity = 1;
                        x = 0;
                    }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }

                    ColumnLayout {
                        id: cardContent
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.notifPadding
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4

                            Text {
                                text: card.appName
                                color: Theme.fg4
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: "󰅖"
                                color: Theme.fg4
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSizeSmall

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.removeNotification(card.nid)
                                }
                            }
                        }

                        Text {
                            text: card.summary
                            color: Theme.fg
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            font.bold: true
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            visible: text !== ""
                        }

                        Text {
                            text: card.body
                            color: Theme.fg3
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            visible: text !== ""
                        }
                    }
                }
            }
        }
    }

    // ══════════════════════════════════════════════
    // ── OSD (Volume & Brightness)
    // ══════════════════════════════════════════════

    // --- Pipewire volume tracking ---
    PwObjectTracker {
        id: osdPwTracker
        objects: [Pipewire.defaultAudioSink]
    }

    property bool osdVolumeInitialized: false
    property bool showOsd: false
    property real osdValue: 0
    property string osdIcon: ""
    property string osdLabel: ""

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null

        function onVolumeChanged() {
            if (!root.osdVolumeInitialized) {
                root.osdVolumeInitialized = true;
                return;
            }
            root.showVolumeOsd();
        }

        function onMutedChanged() {
            if (!root.osdVolumeInitialized) return;
            root.showVolumeOsd();
        }
    }

    function showVolumeOsd() {
        console.log("showVolumeOsd called");
        let sink = Pipewire.defaultAudioSink;
        if (!sink) return;
        let vol = Math.round(sink.audio.volume * 100);
        let muted = sink.audio.muted;

        osdValue = muted ? 0 : Math.min(vol, 100);
        osdLabel = muted ? "Muted" : vol + "%";

        if (muted) {
            osdIcon = "󰝟";
        } else if (vol > 66) {
            osdIcon = "󰕾";
        } else if (vol > 33) {
            osdIcon = "󰖀";
        } else {
            osdIcon = "󰕿";
        }

        showOsd = true;
        osdHideTimer.restart();
    }

    // --- Brightness tracking (triggered by keybind) ---
    property real lastBrightness: -1
    property bool brightnessInitialized: false

    Process {
        id: brightnessProc
        command: ["tail", "-F", "/tmp/quickshell-brightness"]
        running: true

        stdout: SplitParser {
            onRead: data => {
                let parts = data.trim().split(",");
                if (parts.length < 4) return;
                let pct = parseInt(parts[3]);
                if (isNaN(pct)) return;

                if (!root.brightnessInitialized) {
                    root.lastBrightness = pct;
                    root.brightnessInitialized = true;
                    return;
                }

                if (pct !== root.lastBrightness) {
                    root.lastBrightness = pct;
                    root.showBrightnessOsd(pct);
                }
            }
        }
    }

    function showBrightnessOsd(pct) {
        console.log("showBrightnessOsd called, pct=" + pct);
        osdValue = pct;
        osdLabel = pct + "%";
        osdIcon = "󰃟";
        showOsd = true;
        osdHideTimer.restart();
    }

    // --- OSD dismiss timer ---
    Timer {
        id: osdHideTimer
        interval: Theme.osdTimeout
        onTriggered: root.showOsd = false
    }

    // --- OSD Window ---
    LazyLoader {
        active: root.showOsd

        PanelWindow {
            id: osdWindow
            visible: root.showOsd

            anchors { top: true }
            margins { top: Theme.barHeight + Theme.barMargin + Theme.gapOut }

            implicitWidth: Theme.osdWidth
            implicitHeight: Theme.osdHeight
            color: "transparent"

            mask: Region {}

            WlrLayershell.namespace: "quickshell:osd"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            Rectangle {
                anchors.fill: parent
                radius: Theme.osdRadius
                color: Theme.bg1
                border.width: 1
                border.color: Theme.bg3

                Row {
                    anchors.centerIn: parent
                    spacing: 10

                    Text {
                        text: root.osdIcon
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.iconSize
                        color: Theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Rectangle {
                        width: Theme.osdWidth - 100
                        height: Theme.osdBarHeight
                        radius: Theme.osdBarRadius
                        color: Theme.bg3
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            width: parent.width * (root.osdValue / 100)
                            radius: parent.radius
                            color: Theme.greenBright

                            Behavior on width {
                                NumberAnimation { duration: 80 }
                            }
                        }
                    }

                    Text {
                        text: root.osdLabel
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.fg3
                        width: 38
                        horizontalAlignment: Text.AlignRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}