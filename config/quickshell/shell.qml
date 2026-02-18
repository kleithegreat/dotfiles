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
import qs.popups as Popups

Scope {
    id: root

    // ── Popup state ──
    property string activePopup: ""
    function openPopup(name) { activePopup = (activePopup === name) ? "" : name; }

    // ── Notification state ──
    property bool doNotDisturb: false
    property int historyCount: historyModel.count
    function toggleDnd() { doNotDisturb = !doNotDisturb; }

    // ── Bar ──
    Variants {
        model: Quickshell.screens
        Bar.Bar { required property var modelData; screen: modelData; shellRoot: root }
    }

    // ── Notification Server ──
    NotificationServer {
        id: server; bodySupported: true; bodyImagesSupported: true; imageSupported: true; keepOnReload: false
        onNotification: (notification) => {
            let data = { appName: notification.appName || "Notification", summary: notification.summary || "", body: notification.body || "", nid: notification.id };
            historyModel.insert(0, data);
            if (!root.doNotDisturb) {
                notifModel.insert(0, data);
                let timeout = notification.expireTimeout > 0 ? notification.expireTimeout : Theme.notifTimeout;
                dismissTimer.createObject(root, { targetNid: data.nid, interval: timeout });
            }
        }
    }

    Component { id: dismissTimer; Timer { required property int targetNid; running: true; repeat: false; onTriggered: { root.removeNotifPopup(targetNid); this.destroy(); } } }
    ListModel { id: notifModel }
    ListModel { id: historyModel }
    function removeNotifPopup(nid) { for (let i = 0; i < notifModel.count; i++) if (notifModel.get(i).nid === nid) { notifModel.remove(i); break; } }
    function removeHistory(nid) { for (let i = 0; i < historyModel.count; i++) if (historyModel.get(i).nid === nid) { historyModel.remove(i); break; } }
    function clearHistory() { historyModel.clear(); }

    // ── Notification Popups ──
    PanelWindow {
        anchors { top: true; right: true }
        margins { top: Theme.barHeight + Theme.barMargin + Theme.gapOut; right: Theme.gapOut }
        implicitWidth: Theme.notifWidth; implicitHeight: notifColumn.implicitHeight
        visible: notifModel.count > 0; color: "transparent"
        WlrLayershell.namespace: "quickshell:notifications"; WlrLayershell.layer: WlrLayer.Overlay; exclusionMode: ExclusionMode.Ignore

        Column {
            id: notifColumn; spacing: Theme.notifSpacing
            anchors { left: parent.left; right: parent.right; top: parent.top }
            Repeater {
                model: notifModel
                Rectangle {
                    id: card; required property string appName; required property string summary; required property string body; required property int nid; required property int index
                    width: Theme.notifWidth; height: cardC.implicitHeight + Theme.notifPadding * 2; radius: Theme.notifRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
                    opacity: 0; x: 20; Component.onCompleted: { opacity = 1; x = 0; }
                    Behavior on opacity { NumberAnimation { duration: 200 } }
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
                    ColumnLayout {
                        id: cardC; spacing: 4
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.notifPadding }
                        RowLayout { Layout.fillWidth: true
                            Text { text: card.appName; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: "󰅖"; color: pcA.containsMouse ? Theme.redBright : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                MouseArea { id: pcA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: root.removeNotifPopup(card.nid) } }
                        }
                        Text { text: card.summary; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text !== "" }
                        Text { text: card.body; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                    }
                }
            }
        }
    }

    // ── OSD ──
    PwObjectTracker { id: osdPwTracker; objects: [Pipewire.defaultAudioSink] }
    property bool osdVolInit: false; property bool showOsd: false; property real osdValue: 0; property string osdIcon: ""; property string osdLabel: ""

    Connections {
        target: Pipewire.defaultAudioSink?.audio ?? null
        function onVolumeChanged() { if (!root.osdVolInit) { root.osdVolInit = true; return; } root.showVolumeOsd(); }
        function onMutedChanged() { if (!root.osdVolInit) return; root.showVolumeOsd(); }
    }

    function showVolumeOsd() {
        let s = Pipewire.defaultAudioSink; if (!s) return;
        let v = Math.round(s.audio.volume * 100), m = s.audio.muted;
        osdValue = m ? 0 : Math.min(v, 100); osdLabel = m ? "Muted" : v + "%";
        if (m) osdIcon = "󰝟"; else if (v > 66) osdIcon = "󰕾"; else if (v > 33) osdIcon = "󰖀"; else osdIcon = "󰕿";
        showOsd = true; osdHideTimer.restart();
    }

    property real lastBrightness: -1; property bool brightnessInit: false
    Process { id: brightnessProc; command: ["tail", "-F", "/tmp/quickshell-brightness"]; running: true
        stdout: SplitParser { onRead: data => {
            let p = data.trim().split(","); if (p.length < 4) return;
            let pct = parseInt(p[3]); if (isNaN(pct)) return;
            if (!root.brightnessInit) { root.lastBrightness = pct; root.brightnessInit = true; return; }
            if (pct !== root.lastBrightness) { root.lastBrightness = pct; root.showBrightnessOsd(pct); }
        } }
    }
    function showBrightnessOsd(pct) { osdValue = pct; osdLabel = pct + "%"; osdIcon = "󰃟"; showOsd = true; osdHideTimer.restart(); }
    Timer { id: osdHideTimer; interval: Theme.osdTimeout; onTriggered: root.showOsd = false }

    LazyLoader {
        active: root.showOsd
        PanelWindow {
            visible: root.showOsd
            anchors { top: true }
            margins { top: Theme.barHeight + Theme.barMargin + Theme.gapOut }
            implicitWidth: Theme.osdWidth; implicitHeight: Theme.osdHeight; color: "transparent"; mask: Region {}
            WlrLayershell.namespace: "quickshell:osd"; WlrLayershell.layer: WlrLayer.Overlay; exclusionMode: ExclusionMode.Ignore
            Rectangle { anchors.fill: parent; radius: Theme.osdRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
                Row { anchors.centerIn: parent; spacing: 10
                    Text { text: root.osdIcon; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter }
                    Rectangle { width: Theme.osdWidth - 100; height: Theme.osdBarHeight; radius: Theme.osdBarRadius; color: Theme.bg3; anchors.verticalCenter: parent.verticalCenter
                        Rectangle {
                            width: parent.width * (root.osdValue / 100); radius: parent.radius; color: Theme.greenBright
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                            Behavior on width { NumberAnimation { duration: 80 } }
                        }
                    }
                    Text { text: root.osdLabel; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.fg3; width: 38; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
                }
            }
        }
    }

    // ── All Popups (bound to activePopup) ──
    PowerMenu { active: root.activePopup === "powermenu"; onClose: root.activePopup = "" }
    NotifDrawer {
        active: root.activePopup === "drawer"; onClose: root.activePopup = ""
        model: historyModel; doNotDisturb: root.doNotDisturb
        onToggleDnd: root.toggleDnd(); onClearAll: root.clearHistory(); onRemoveItem: (nid) => root.removeHistory(nid)
    }
    Popups.CalendarPopup { active: root.activePopup === "calendar"; onClose: root.activePopup = "" }
    Popups.TrayPopup { active: root.activePopup === "tray"; onClose: root.activePopup = "" }
    Popups.MprisPopup { active: root.activePopup === "mpris"; onClose: root.activePopup = "" }
    Popups.AudioPopup { active: root.activePopup === "audio"; onClose: root.activePopup = "" }
    Popups.WifiPopup { active: root.activePopup === "wifi"; onClose: root.activePopup = "" }
    Popups.PowerProfilePopup { active: root.activePopup === "powerprofile"; onClose: root.activePopup = "" }
}
