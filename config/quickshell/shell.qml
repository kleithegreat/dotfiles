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

    Timer {
        interval: 1000
        running: true
        repeat: false
        onTriggered: IdleInhibitService.applyBootDefault()
    }

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
        let fallbackName = "";
        for (let i = 0; i < monitors.length; ++i) {
            const monitor = monitors[i];
            if (!root.isRealMonitor(monitor))
                continue;

            if (fallbackName === "")
                fallbackName = monitor.name;

            if (monitor.x === 0 && monitor.y === 0)
                return monitor.name;
        }

        return fallbackName;
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
                DisplayService.refreshMonitors();
                BrightnessService.refresh();
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
                    opacity: 0; x: Theme.notifWidth * 0.5; scale: Theme.popupStartScale
                    Component.onCompleted: { notifEnterAnim.start(); }

                    SequentialAnimation {
                        id: notifEnterAnim
                        PauseAnimation { duration: card.index * Theme.animStagger }
                        ParallelAnimation {
                            Components.Anim { target: card; property: "opacity"; from: 0; to: 1; duration: Theme.animNotifIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveEmphasizedEnter }
                            Components.Anim { target: card; property: "x"; from: Theme.notifWidth * 0.5; to: 0; duration: Theme.animNotifIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveEmphasizedEnter }
                            Components.Anim { target: card; property: "scale"; from: Theme.popupStartScale; to: 1.0; duration: Theme.animNotifIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Theme.animCurveEmphasizedEnter }
                        }
                    }
                    ColumnLayout {
                        id: cardC; spacing: 4
                        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Theme.notifPadding }
                        RowLayout { Layout.fillWidth: true
                            Text { text: card.appName; color: Theme.fg4; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; elide: Text.ElideRight; Layout.fillWidth: true }
                            Components.Icon { source: "../icons/close.svg"; color: pcA.containsMouse ? Theme.redBright : Theme.fg4; iconSize: Theme.fontSizeSmall
                                MouseArea { id: pcA; anchors.fill: parent; cursorShape: Qt.PointingHandCursor; hoverEnabled: true; onClicked: NotificationService.removeNotifPopup(card.nid) } }
                        }
                        Text { text: card.summary; color: Theme.fg; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize; font.bold: true; wrapMode: Text.WordWrap; Layout.fillWidth: true; visible: text !== "" }
                        Text { text: card.body; color: Theme.fg3; font.family: Theme.systemFamily; font.pixelSize: Theme.fontSizeSmall; wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; Layout.fillWidth: true; visible: text !== "" }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "brightness"
        function osd(percent: string): void {
            let pct = parseInt(percent);
            if (!isNaN(pct)) {
                BrightnessService.refresh();
                AudioService.showOsdState(pct, pct + "%", "../icons/brightness-medium.svg");
            }
        }
    }

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
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.popupPadding
                anchors.rightMargin: Theme.popupPadding
                spacing: 10

                Components.Icon {
                    source: AudioService.osdIcon
                    color: Theme.fg
                    Layout.alignment: Qt.AlignVCenter
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.minimumWidth: Math.max(Theme.fontSize * 8, 72)
                    height: Theme.osdBarHeight
                    radius: Theme.osdBarRadius
                    color: Theme.bg3
                    Layout.alignment: Qt.AlignVCenter
                    Rectangle {
                        width: parent.width * (AudioService.osdValue / 100); radius: parent.radius; color: Theme.greenBright
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                        Behavior on width { Components.Anim { duration: Theme.animFast; easing.type: Easing.OutCubic } }
                    }
                }
                Text {
                    text: AudioService.osdLabel
                    font.family: Theme.systemFamily
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.fg3
                    elide: Text.ElideRight
                    Layout.preferredWidth: Math.min(implicitWidth, Math.max(Theme.fontSize * 5, 56))
                    Layout.maximumWidth: Math.round(osdPanel.width * 0.3)
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    // ── Toast ──
    PanelWindow {
        visible: ToastService.toastVisible || toastPanel.opacity > 0.001
        anchors { bottom: true }
        margins { bottom: Theme.gapOut }
        implicitWidth: Math.min(toastContent.implicitWidth + Theme.popupPadding * 2, Math.max(Theme.osdWidth, (root.barScreen ? root.barScreen.width : 900) - Theme.gapOut * 4))
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

                Components.Icon {
                    source: ToastService.currentLevel === "error" ? "../icons/circle-x.svg" :
                            ToastService.currentLevel === "warning" ? "../icons/alert-triangle.svg" : "../icons/info-circle.svg"
                    color: ToastService.currentLevel === "error"   ? Theme.redBright :
                           ToastService.currentLevel === "warning" ? Theme.yellowBright : Theme.fg
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    text: ToastService.currentMessage
                    font.family: Theme.systemFamily; font.pixelSize: Theme.fontSize
                    color: Theme.fg
                    width: Math.min(implicitWidth, Math.max(Theme.osdWidth, (root.barScreen ? root.barScreen.width : 900) - Theme.popupPadding * 2 - Theme.gapOut * 4 - 32))
                    elide: Text.ElideRight
                    maximumLineCount: 1
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
            else
                ToastService.showInfo("Theme command completed");

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

            if (themeApplyProc.running) {
                ToastService.showWarning("Theme command already running");
                return;
            }

            themeApplyProc.output = "";
            themeApplyProc.command = ["desktopctl", "theme"].concat(parsed.argv);
            themeApplyProc.running = true;
        }
    }

    IpcHandler {
        target: "toast"

        function info(message: string): void { ToastService.showInfo(message); }
        function warning(message: string): void { ToastService.showWarning(message); }
        function error(message: string): void { ToastService.showError(message); }
    }
}
