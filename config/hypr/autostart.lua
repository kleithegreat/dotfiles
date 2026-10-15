local exec = require("./session").exec

hl.on("hyprland.start", function()
    -- Export the environment (SSH_AUTH_SOCK at the home/shell.nix fallback path) before the
    -- session target; graphical-session.target refuses a manual start, so the fake one pulls it in.
    exec([[sh -c 'export SSH_AUTH_SOCK="${XDG_RUNTIME_DIR}/gcr/ssh"; dbus-update-activation-environment --systemd --all; dbus-update-activation-environment HL_INITIAL_WORKSPACE_TOKEN= XDG_ACTIVATION_TOKEN= DESKTOP_STARTUP_ID=; systemctl --user unset-environment HL_INITIAL_WORKSPACE_TOKEN XDG_ACTIVATION_TOKEN DESKTOP_STARTUP_ID; systemctl --user start nixos-fake-graphical-session.target xdg-desktop-portal.service xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service hyprpolkitagent']])

    -- `desktopctl.service` is pulled in by graphical-session.target above.
    exec("desktopctl launch-quickshell")

    exec("vicinae server")

    -- Both daemons start alongside; each wait is handled by the wallpaper target.
    exec([[sh -c 'awww-daemon & desktopctl theme wallpaper --wait-daemon 15']])

    exec("snappy-switcher --daemon")

    exec("solaar -w hide")
    exec([[solaar config "MX Master 2S" smart-shift 50]])

    exec("desktopctl session restore --if-automatic --wait-daemon 15")
end)

hl.on("hyprland.shutdown", function()
    hl.exec_cmd("systemctl --user stop nixos-fake-graphical-session.target")
end)

require("./autostart-host")
