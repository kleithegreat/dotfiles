{ pkgs, lib, ... }:

{
  # The daemon is the single writer of mutable desktop state, and every write
  # subcommand hard-fails without it — so it is supervised rather than spawned
  # from a compositor autostart line. `graphical-session.target` is started by
  # `config/hypr/autostart.lua` after the session environment is exported to
  # systemd, and stopped on `hyprland.shutdown`, so the daemon inherits
  # WAYLAND_DISPLAY/HYPRLAND_INSTANCE_SIGNATURE and dies with the session.
  systemd.user.services.desktopctl = {
    Unit = {
      Description = "desktopctl desktop daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${lib.getExe pkgs.optimized.desktopctl} daemon";
      Restart = "on-failure";
      RestartSec = 1;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  home.activation.applyTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH="${lib.makeBinPath [ pkgs.optimized.desktopctl ]}:$PATH"
    mkdir -p "$HOME/.config/hypr"
    # Seed the desktopctl-managed data tables. An empty file is the "no
    # overrides" state: the Lua appliers guard their require, and `desktopctl
    # hypr animations clear` truncates back to empty.
    touch "$HOME/.config/hypr/input-runtime.lua"
    touch "$HOME/.config/hypr/displays-runtime.lua"
    touch "$HOME/.config/hypr/animations-override-data.lua"
    desktopctl theme sync
  '';
}
