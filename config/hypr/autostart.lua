-- Autostart

local session = require("./session")
local exec = session.exec

hl.on("hyprland.start", function()
    -- Session — export SSH_AUTH_SOCK at the gcr-ssh-agent.socket path (%t/gcr/ssh,
    -- matching the home/shell.nix fallback) so it lands in the activation env,
    -- scrub one-shot launch/workspace tokens, then propagate the remaining full
    -- environment to D-Bus + systemd before starting activation-sensitive user units.
    --
    -- `graphical-session.target` is `RefuseManualStart=yes`, so it can only be
    -- pulled up as a dependency: nixos-fake-graphical-session.target `BindsTo=`
    -- it, and the target's `StopWhenUnneeded=yes` takes it back down with us.
    exec([[sh -c 'export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/gcr/ssh"; dbus-update-activation-environment --systemd --all; dbus-update-activation-environment HL_INITIAL_WORKSPACE_TOKEN= XDG_ACTIVATION_TOKEN= DESKTOP_STARTUP_ID=; systemctl --user unset-environment HL_INITIAL_WORKSPACE_TOKEN XDG_ACTIVATION_TOKEN DESKTOP_STARTUP_ID; systemctl --user start nixos-fake-graphical-session.target xdg-desktop-portal.service xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service hyprpolkitagent']])

    -- `desktopctl.service` is pulled in by graphical-session.target above.
    exec("desktopctl launch-quickshell")

    exec("vicinae server")

    -- Wallpaper. Both daemons spawn alongside this and the apply waits each of
    -- them out on its own: --wait-daemon for desktopctl, an awww socket poll
    -- inside the wallpaper target for awww-daemon.
    exec([[sh -c 'awww-daemon & desktopctl theme wallpaper --wait-daemon 15']])

    -- Window switcher
    exec("snappy-switcher --daemon")
end)

hl.on("hyprland.shutdown", function()
    hl.exec_cmd("systemctl --user stop nixos-fake-graphical-session.target")
end)

-- Host-specific autostart hooks
require("./autostart-host")
