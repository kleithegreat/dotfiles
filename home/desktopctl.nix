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

  # Open With → AirDrop: the files go to the shell's share card ([[airdrop]]).
  xdg.desktopEntries.airdrop = {
    name = "AirDrop";
    comment = "Share with iPhones nearby";
    icon = "network-wireless";
    exec = "${lib.getExe pkgs.optimized.desktopctl} airdrop share %F";
    noDisplay = true;
    mimeType = [ "all/all" "all/allfiles" ];
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
