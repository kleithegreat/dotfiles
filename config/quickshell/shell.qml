import Quickshell
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
        void Sys.AirPods.connected;
        void Sys.AirDrop.available;
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

    Surfaces.Proximity {
        screen: shell.primaryScreen
    }

    Surfaces.AirDrop {
        screen: shell.primaryScreen
    }

    // Shortcut names are surface names; config/hypr/keybinds.lua binds them.
    Variants {
        model: ["session", "notifications", "settings"]

        GlobalShortcut {
            required property string modelData

            name: modelData
            onPressed: shell.state.open(modelData)
        }
    }
}
