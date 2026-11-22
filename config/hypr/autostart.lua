local exec = require("./session").exec

hl.on("hyprland.start", function()
    -- Export the environment, then start this instance's anchor, which pulls in graphical-session.target.
    exec([[sh -c 'dbus-update-activation-environment --systemd --all; dbus-update-activation-environment HL_INITIAL_WORKSPACE_TOKEN= XDG_ACTIVATION_TOKEN= DESKTOP_STARTUP_ID=; systemctl --user unset-environment HL_INITIAL_WORKSPACE_TOKEN XDG_ACTIVATION_TOKEN DESKTOP_STARTUP_ID; systemctl --user start "hyprland-session@${HYPRLAND_INSTANCE_SIGNATURE}.service" xdg-desktop-portal.service xdg-desktop-portal-hyprland.service xdg-desktop-portal-gtk.service hyprpolkitagent.service; desktopctl session restore --if-automatic --wait-daemon 15']])

    -- `desktopctl.service` is pulled in by graphical-session.target above.
    exec("desktopctl launch-quickshell")

    exec("vicinae server")

    -- Both daemons start alongside; each wait is handled by the wallpaper target.
    exec([[sh -c 'awww-daemon & desktopctl theme wallpaper --wait-daemon 15']])

    exec("snappy-switcher --daemon")

    exec("solaar --window=hide")
    exec([[solaar config "MX Master 2S" smart-shift 50]])
end)

require("./autostart-host")
