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

    // Bar lifetime follows Hyprland's monitor model, not Quickshell.screens:
    // output churn (suspend, DPMS, hotplug) tears down the layer surface while
    // Qt keeps a placeholder QScreen alive, so `screens` never reports that the
    // outputs are gone.
    readonly property string barMonitor: {
        const monitors = Hyprland.monitors.values;
        let fallback = "";
        for (let i = 0; i < monitors.length; i++) {
            const monitor = monitors[i];
            if (!monitor || monitor.id < 0 || monitor.name === "FALLBACK")
                continue;
            if (fallback === "")
                fallback = monitor.name;
            if (monitor.x === 0 && monitor.y === 0)
                return monitor.name;
        }
        return fallback;
    }

    readonly property var barScreen: {
        if (barMonitor === "")
            return null;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++) {
            const monitor = Hyprland.monitorFor(screens[i]);
            if (monitor && monitor.name === barMonitor)
                return screens[i];
        }
        return null;
    }

    // Services are created on first reference. The ones that poll or hold a
    // subscription have to exist from the start, whether or not anything is
    // currently looking at them.
    Component.onCompleted: {
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
        void Sys.Appearance.state;
        Sys.Idle.applyBootDefault();
    }

    Loader {
        id: barLoader
        active: shell.barScreen !== null

        sourceComponent: Bar.Bar {
            screen: shell.barScreen
            state: shell.state
        }
    }

    Surfaces.Overlay {
        state: shell.state
        barWindow: barLoader.item
    }

    Surfaces.Hint {}

    Surfaces.Osd {}

    Surfaces.Toasts {}

    Surfaces.Banners {}

    // These names are the shell's published interface: config/hypr/keybinds.lua
    // calls them. Renaming them here silently breaks the keybinds until the next
    // Home Manager rebuild, which is a long time to leave Super+T dead.
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

    IpcHandler {
        target: "audio"

        function toggleMute(): void {
            Sys.Audio.toggleMute();
        }
        function raise(): void {
            Sys.Audio.nudge(0.05);
        }
        function lower(): void {
            Sys.Audio.nudge(-0.05);
        }
        function status(): string {
            return JSON.stringify({ volume: Sys.Audio.percent, muted: Sys.Audio.muted, sink: Sys.Audio.sinkName });
        }
    }

    IpcHandler {
        target: "brightness"

        // The hotkeys write brightness through desktopctl directly; this only
        // reports what they did.
        function osd(percent: string): void {
            Sys.Brightness.refresh();
            Sys.Osd.show(Sys.Brightness.icon, parseInt(percent, 10) / 100, percent + "%");
        }
    }

    IpcHandler {
        target: "notifications"

        function toggleDnd(): void {
            Sys.Notifications.toggleDnd();
        }
        function clear(): void {
            Sys.Notifications.clearHistory();
        }
    }

    IpcHandler {
        target: "vpn"

        function mullvad(on: string): void {
            Sys.Mullvad.set(on === "on");
        }
        function tailscale(on: string): void {
            Sys.Tailscale.set(on === "on");
        }
        function status(): string {
            return JSON.stringify({ mullvad: Sys.Mullvad.state, location: Sys.Mullvad.location, tailscale: Sys.Tailscale.state, ip: Sys.Tailscale.ip });
        }
    }

    IpcHandler {
        target: "toast"

        function info(message: string): void {
            Sys.Toast.info(message);
        }
        function warning(message: string): void {
            Sys.Toast.warning(message);
        }
        function error(message: string): void {
            Sys.Toast.error(message);
        }
    }
}
