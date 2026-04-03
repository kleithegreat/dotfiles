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

    // Drive bar lifetime from Hyprland's real monitor model; Qt keeps a
    // placeholder screen alive when all outputs disappear.
    function isRealMonitor(monitor) {
        return monitor && monitor.id >= 0 && monitor.name !== "FALLBACK";
    }

    function tokenizeThemeArgs(payload) {
        if (Array.isArray(payload)) {
            return {
                argv: payload.map(part => String(part)),
                error: ""
            };
        }

        let text = payload === undefined || payload === null ? "" : String(payload);
        let argv = [];
        let current = "";
        let quote = "";
        let escaping = false;

        for (let i = 0; i < text.length; ++i) {
            let ch = text.charAt(i);

            if (escaping) {
                current += ch;
                escaping = false;
                continue;
            }

            if (quote === "'") {
                if (ch === "'") {
                    quote = "";
                } else {
                    current += ch;
                }
                continue;
            }

            if (quote === "\"") {
                if (ch === "\"") {
                    quote = "";
                    continue;
                }
                if (ch === "\\") {
                    escaping = true;
                    continue;
                }

                current += ch;
                continue;
            }

            if (ch === "'" || ch === "\"") {
                quote = ch;
                continue;
            }

            if (ch === "\\") {
                escaping = true;
                continue;
            }

            if (/\s/.test(ch)) {
                if (current !== "") {
                    argv.push(current);
                    current = "";
                }
                continue;
            }

            current += ch;
        }

        if (escaping)
            current += "\\";

        if (quote !== "") {
            return {
                argv: [],
                error: "theme.apply received an unterminated quoted argument"
            };
        }

        if (current !== "")
            argv.push(current);

        return {
            argv: argv,
            error: ""
        };
    }

    readonly property string barMonitorName: {
        const monitors = Hyprland.monitors.values;
        for (let i = 0; i < monitors.length; ++i) {
            const monitor = monitors[i];
            if (root.isRealMonitor(monitor)) {
                return monitor.name;
            }
        }

        return "";
    }

    readonly property var barScreen: {
        if (root.barMonitorName === "") {
            return null;
        }

        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; ++i) {
            const screen = screens[i];
            const monitor = Hyprland.monitorFor(screen);
            if (root.isRealMonitor(monitor) && monitor.name === root.barMonitorName) {
                return screen;
            }
        }

        return null;
    }

    // ── Notification state (compat for existing popup/bar wiring) ──
    readonly property bool doNotDisturb: NotificationService.doNotDisturb
    readonly property int historyCount: NotificationService.historyCount

    // ── Tooltip ──
    TooltipWindow {}

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "monitoradded" || event.name === "monitorremoved") {
                Hyprland.refreshMonitors();
            }
        }
    }

    // ── Bar ──
    Loader {
        active: root.barMonitorName !== "" && root.barScreen !== null

        sourceComponent: Bar.Bar {
            screen: root.barScreen
            popupVisibility: root.popupVisibility
            doNotDisturb: root.doNotDisturb
            historyCount: root.historyCount
        }
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
                            Text { text: card.appName; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                            Text { text: "󰅖"; color: pcA.containsMouse ? Theme.redBright : Theme.fg4; font.family: Theme.fontFamily; font.pixelSize: Theme.fontSizeSmall
                                MouseArea { id: pcA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: NotificationService.removeNotifPopup(card.nid) } }
                        }
                        Text { text: card.summary; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text !== "" }
                        Text { text: card.body; color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
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
                Text { text: AudioService.osdLabel; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; color: Theme.fg3; width: 38; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }

    // ── Toast ──
    PanelWindow {
        visible: ToastService.toastVisible || toastPanel.opacity > 0.001
        anchors { bottom: true }
        margins { bottom: Theme.gapOut }
        implicitWidth: toastContent.implicitWidth + Theme.popupPadding * 2
        implicitHeight: Theme.osdHeight
        color: "transparent"; mask: Region {}
        WlrLayershell.namespace: "quickshell:toast"; WlrLayershell.layer: WlrLayer.Overlay; exclusionMode: ExclusionMode.Ignore

        Rectangle {
            id: toastPanel
            anchors.fill: parent
            radius: Theme.osdRadius
            color: ToastService.currentLevel === "error"   ? Qt.rgba(Theme.red.r, Theme.red.g, Theme.red.b, 0.25) :
                   ToastService.currentLevel === "warning" ? Qt.rgba(Theme.yellow.r, Theme.yellow.g, Theme.yellow.b, 0.25) :
                   Theme.bg1
            border.width: 1; border.color: Theme.bg3
            scale: ToastService.toastVisible ? 1.0 : 0.85
            opacity: ToastService.toastVisible ? 1.0 : 0.0

            Behavior on scale {
                Components.Anim {
                    duration: ToastService.toastVisible ? Theme.animOsdIn : Theme.animOsdOut
                    easing.type: ToastService.toastVisible ? Easing.OutCubic : Easing.InCubic
                }
            }
            Behavior on opacity {
                Components.Anim {
                    duration: ToastService.toastVisible ? Theme.animOsdIn : Theme.animOsdOut
                    easing.type: ToastService.toastVisible ? Easing.OutCubic : Easing.InCubic
                }
            }

            Row {
                id: toastContent
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: ToastService.currentLevel === "error" ? "󰅚" :
                          ToastService.currentLevel === "warning" ? "󰀪" : "󰋽"
                    font.family: Theme.fontFamily; font.pixelSize: Theme.iconSize
                    color: ToastService.currentLevel === "error"   ? Theme.redBright :
                           ToastService.currentLevel === "warning" ? Theme.yellowBright : Theme.fg
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: ToastService.currentMessage
                    font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize
                    color: Theme.fg
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ── Shared Overlay Host ──
    PopupOverlayHost { popupVisibility: root.popupVisibility }

    IpcHandler {
        target: "popups"

        function closeAll(): void { root.popupVisibility.closeAll(); }
        function togglePowerMenu(): void { root.popupVisibility.togglePowerMenu(); }
        function toggleDrawer(): void { root.popupVisibility.toggleDrawer(); }
        function toggleCalendar(): void { root.popupVisibility.toggleCalendar(); }
        function toggleTray(): void { root.popupVisibility.toggleTray(); }
        function toggleMpris(): void { root.popupVisibility.toggleMpris(); }
        function toggleSettings(): void { root.popupVisibility.toggleSettings(); }
        function toggleQuickSettings(): void { root.popupVisibility.toggleQuickSettings(); }
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

    IpcHandler {
        target: "audio"

        function toggleMute(): void { AudioService.toggleMute(); }
        function status(): string {
            return JSON.stringify({
                volume: Math.round(AudioService.volume * 100),
                muted: AudioService.muted,
                sinkName: AudioService.sinkDescription
            });
        }
    }

    IpcHandler {
        target: "vpn"

        function mullvadConnect(): void { VpnService.mullvadConnect(); }
        function mullvadDisconnect(): void { VpnService.mullvadDisconnect(); }
        function tailscaleUp(): void { VpnService.tailscaleUp(); }
        function tailscaleDown(): void { VpnService.tailscaleDown(); }
        function refresh(): void { VpnService.refresh(); }
        function status(): string {
            return JSON.stringify({
                mullvadState: VpnService.mullvadState,
                mullvadCity: VpnService.mullvadCity,
                tailscaleState: VpnService.tailscaleState,
                tailscaleIp: VpnService.tailscaleIp
            });
        }
    }

    Process {
        id: themeApplyProc
        running: false
        property string output: ""
        stdout: SplitParser { onRead: data => { themeApplyProc.output += data; } }
        stderr: SplitParser { onRead: data => { themeApplyProc.output += data; } }
        onExited: (code, status) => {
            let message = themeApplyProc.output.trim();
            if (code !== 0)
                ToastService.showError(message !== "" ? message : "Theme command failed");

            themeApplyProc.output = "";
        }
    }

    IpcHandler {
        target: "theme"

        function open(): void { root.popupVisibility.toggleSettings(); }
        function apply(args): void {
            let parsed = root.tokenizeThemeArgs(args);
            if (parsed.error !== "") {
                ToastService.showError(parsed.error);
                return;
            }

            if (parsed.argv.length === 0) {
                ToastService.showError("theme.apply requires at least one argument");
                return;
            }

            themeApplyProc.output = "";
            themeApplyProc.command = ["desktopctl", "theme"].concat(parsed.argv);
            themeApplyProc.running = true;
        }
    }

    IpcHandler {
        target: "toast"

        function info(message): void { ToastService.showInfo(message); }
        function warning(message): void { ToastService.showWarning(message); }
        function error(message): void { ToastService.showError(message); }
    }
}
