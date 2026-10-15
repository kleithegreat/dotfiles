{ pkgs, lib, ... }:

{
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
    mkdir --parents "$HOME/.config/hypr"
    # Empty is the "no overrides" state the Lua appliers expect.
    touch "$HOME/.config/hypr/input-runtime.lua"
    touch "$HOME/.config/hypr/displays-runtime.lua"
    desktopctl theme sync
  '';
}
