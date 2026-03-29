import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.bar as Bar
import qs.popups as Popups
import "components" as Components

Scope {
    id: root

    // ── Popup state ──
    property QtObject popupVisibility: PopupVisibility {}

    // ── Notification state (compat for existing popup/bar wiring) ──
    readonly property bool doNotDisturb: NotificationService.doNotDisturb
    readonly property int historyCount: NotificationService.historyCount

    // ── Bar ──
    Bar.Bar {
        popupVisibility: root.popupVisibility
        doNotDisturb: root.doNotDisturb
        historyCount: root.historyCount
    }

    // ── Notification Popups ──
    PanelWindow {
        anchors { top: true; right: true }
        margins { top: Theme.barHeight + Theme.barMargin + Theme.gapOut; right: Theme.gapOut }
        implicitWidth: Theme.notifWidth; implicitHeight: notifColumn.implicitHeight
        visible: NotificationService.popupModel.count > 0; color: "transparent"
        WlrLayershell.namespace: "quickshell:notifications"; WlrLayershell.layer: WlrLayer.Overlay; exclusionMode: ExclusionMode.Ignore

        Column {
            id: notifColumn; spacing: Theme.notifSpacing
            anchors { left: parent.left; right: parent.right; top: parent.top }
            Repeater {
                model: NotificationService.popupModel
                Rectangle {
                    id: card; required property string appName; required property string summary; required property string body; required property int nid; required property int index
                    width: Theme.notifWidth; height: cardC.implicitHeight + Theme.notifPadding * 2; radius: Theme.notifRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
                    opacity: 0; x: Theme.notifWidth * 0.5; scale: 0.92
                    Component.onCompleted: { notifEnterAnim.start(); }

                    SequentialAnimation {
                        id: notifEnterAnim
                        PauseAnimation { duration: card.index * Theme.animStagger }
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.animNotifIn; easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "x"; from: Theme.notifWidth * 0.5; to: 0; duration: Theme.animNotifIn; easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "scale"; from: 0.92; to: 1.0; duration: Theme.animNotifIn; easing.type: Easing.OutCubic }
                        }
                    }
                    ColumnLayout {
                        id: cardC; spacing: 4
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.notifPadding }
                        RowLayout { Layout.fillWidth: true
                            Text { text: card.appName; color: Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: "󰅖"; color: pcA.containsMouse ? Theme.redBright : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                MouseArea { id: pcA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: NotificationService.removeNotifPopup(card.nid) } }
                        }
                        Text { text: card.summary; color: Theme.fg; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSize; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text !== "" }
                        Text { text: card.body; color: Theme.fg3; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                    }
                }
            }
        }
    }

    property real lastBrightness: -1; property bool brightnessInit: false
    Process { id: brightnessProc; command: ["tail", "-F", "/tmp/quickshell-brightness"]; running: true
        stdout: SplitParser { onRead: data => {
            let p = data.trim().split(","); if (p.length < 4) return;
            let rawPct = parseInt(p[3]); if (isNaN(rawPct)) return;
            let pct = Math.round(Math.pow(rawPct / 100, 1.0 / 2.2) * 100);
            if (!root.brightnessInit) { root.lastBrightness = pct; root.brightnessInit = true; return; }
            if (pct !== root.lastBrightness) { root.lastBrightness = pct; root.showBrightnessOsd(pct); }
        } }
    }
    function showBrightnessOsd(pct) { AudioService.showOsdState(pct, pct + "%", "󰃟"); }

    PanelWindow {
        visible: AudioService.showOsd || osdPanel.opacity > 0.001
        anchors { top: true }
        margins { top: Theme.barHeight + Theme.barMargin + Theme.gapOut }
        implicitWidth: Theme.osdWidth; implicitHeight: Theme.osdHeight; color: "transparent"; mask: Region {}
        WlrLayershell.namespace: "quickshell:osd"; WlrLayershell.layer: WlrLayer.Overlay; exclusionMode: ExclusionMode.Ignore
        Rectangle {
            id: osdPanel
            anchors.fill: parent
            radius: Theme.osdRadius; color: Theme.bg1; border.width: 1; border.color: Theme.bg3
            scale: AudioService.showOsd ? 1.0 : 0.85
            opacity: AudioService.showOsd ? 1.0 : 0.0
            Behavior on scale {
                Components.Anim {
                    duration: AudioService.showOsd ? Theme.animOsdIn : Theme.animOsdOut
                    easing.type: AudioService.showOsd ? Easing.OutCubic : Easing.InCubic
                }
            }
            Behavior on opacity {
                Components.Anim {
                    duration: AudioService.showOsd ? Theme.animOsdIn : Theme.animOsdOut
                    easing.type: AudioService.showOsd ? Easing.OutCubic : Easing.InCubic
                }
            }
            Row { anchors.centerIn: parent; spacing: 10
                Text { text: AudioService.osdIcon; font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize; color: Theme.fg; anchors.verticalCenter: parent.verticalCenter }
                Rectangle { width: Theme.osdWidth - 100; height: Theme.osdBarHeight; radius: Theme.osdBarRadius; color: Theme.bg3; anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        width: parent.width * (AudioService.osdValue / 100); radius: parent.radius; color: Theme.greenBright
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        Behavior on width { Components.Anim { duration: 80; easing.type: Easing.OutCubic } }
                    }
                }
                Text { text: AudioService.osdLabel; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.fg3; width: 38; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // ── Shared Overlay Host ──
    PopupOverlayHost { popupVisibility: root.popupVisibility }

    // ── Remaining Popups (bound to popupVisibility) ──
    // PowerMenu { active: root.popupVisibility.powerMenuVisible; onClose: root.popupVisibility.powerMenuVisible = false }
    // NotifDrawer {
    //     active: root.popupVisibility.drawerVisible; onClose: root.popupVisibility.drawerVisible = false
    // }
    // Popups.CalendarPopup { active: root.popupVisibility.calendarVisible; onClose: root.popupVisibility.calendarVisible = false }
    // Popups.TrayPopup { active: root.popupVisibility.trayVisible; onClose: root.popupVisibility.trayVisible = false }
    // Popups.MprisPopup { active: root.popupVisibility.mprisVisible; onClose: root.popupVisibility.mprisVisible = false }
    // Popups.AudioPopup { active: root.popupVisibility.audioVisible; onClose: root.popupVisibility.audioVisible = false }
    // Popups.WifiPopup { active: root.popupVisibility.wifiVisible; onClose: root.popupVisibility.wifiVisible = false }
    // Popups.BluetoothPopup { active: root.popupVisibility.bluetoothVisible; onClose: root.popupVisibility.bluetoothVisible = false }
    // Popups.PowerProfilePopup { active: root.popupVisibility.powerProfileVisible; onClose: root.popupVisibility.powerProfileVisible = false }
    // Popups.SettingsPopup { active: root.popupVisibility.settingsVisible; onClose: root.popupVisibility.settingsVisible = false }

    IpcHandler {
        target: "popups"

        function closeAll(): void { root.popupVisibility.closeAll(); }
        function togglePowerMenu(): void { root.popupVisibility.togglePowerMenu(); }
        function toggleDrawer(): void { root.popupVisibility.toggleDrawer(); }
        function toggleCalendar(): void { root.popupVisibility.toggleCalendar(); }
        function toggleTray(): void { root.popupVisibility.toggleTray(); }
        function toggleMpris(): void { root.popupVisibility.toggleMpris(); }
        function toggleAudio(): void { root.popupVisibility.toggleAudio(); }
        function toggleWifi(): void { root.popupVisibility.toggleWifi(); }
        function toggleBluetooth(): void { root.popupVisibility.toggleBluetooth(); }
        function togglePowerProfile(): void { root.popupVisibility.togglePowerProfile(); }
        function toggleSettings(): void { root.popupVisibility.toggleSettings(); }
        function toggleVpn(): void { root.popupVisibility.toggleVpn(); }
    }

    IpcHandler {
        target: "notifications"

        function toggleDnd(): void { NotificationService.toggleDnd(); }
        function clearHistory(): void { NotificationService.clearHistory(); }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void { root.popupVisibility.toggleSettings(); }
    }
}
