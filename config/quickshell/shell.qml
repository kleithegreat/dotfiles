import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import qs.bar as Bar
import qs.surfaces as Surfaces
import qs.services as Sys

Scope {
    id: shell

    readonly property ShellState state: ShellState {}

    // Fallback only: the daemon's answer wins ([[quickshell]], [[desktopctl]]).
    readonly property string primaryMonitor: {
        const monitors = Hyprland.monitors.values;
        let fallback = "";
        for (let i = 0; i < monitors.length; i++) {
            const monitor = monitors[i];
            if (!monitor || monitor.id < 0 || monitor.name === "FALLBACK")
                continue;
            if (fallback === "")
                fallback = monitor.name;
            if (monitor.name === Sys.Displays.primaryOutput)
                return monitor.name;
        }
        return fallback;
    }

    readonly property var primaryScreen: {
        if (primaryMonitor === "")
            return null;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            const monitor = Hyprland.monitorFor(screens[i]);
            if (monitor && monitor.name === primaryMonitor)
                return screens[i];
        }
        return null;
    }

    // Load-bearing: singletons that poll or subscribe exist only once referenced.
    Component.onCompleted: {
        void Sys.Desktopctl.ready;
        void Sys.Network.label;
        void Sys.Bluetooth.available;
        void Sys.Audio.percent;
        void Sys.Brightness.available;
        void Sys.Power.present;
        void Sys.Notifications.historyCount;
        void Sys.Compositor.blurEnabled;
        void Sys.Mullvad.state;
        void Sys.Tailscale.state;
        void Sys.NightLight.mode;
        void Sys.SessionRestore.restorable;
        void Sys.Appearance.state;
        void Sys.Displays.primaryOutput;
        Sys.Idle.applyBootDefault();
    }

    Loader {
        id: barLoader
        active: shell.primaryScreen !== null

        sourceComponent: Bar.Bar {
            screen: shell.primaryScreen
            state: shell.state
        }
    }

    // Every surface names the bar's screen; see docs/quickshell.md.
    Surfaces.Overlay {
        screen: shell.primaryScreen
        state: shell.state
        barWindow: barLoader.item
    }

    Surfaces.Hint {
        screen: shell.primaryScreen
    }

    Surfaces.Osd {
        screen: shell.primaryScreen
    }

    Surfaces.Toasts {
        screen: shell.primaryScreen
    }

    Surfaces.Banners {
        screen: shell.primaryScreen
    }

    // Published interface: config/hypr/keybinds.lua calls these names.
    IpcHandler {
        target: "popups"

        function togglePowerMenu(): void {
            shell.state.open("session");
        }
        function toggleDrawer(): void {
            shell.state.open("notifications");
        }
        function toggleControl(): void {
            shell.state.open("control");
        }
        function toggleCalendar(): void {
            shell.state.open("calendar");
        }
        function toggleMedia(): void {
            shell.state.open("media");
        }
        function closeAll(): void {
            shell.state.close();
        }
    }

    IpcHandler {
        target: "settings"

        function toggle(): void {
            if (shell.state.isOpen("settings"))
                shell.state.close();
            else
                shell.state.showSettings();
        }
        function pane(name: string): void {
            shell.state.showSettings(name);
        }
    }
}
