{
  config,
  lib,
  pkgs,
  ...
}:

{
  home.packages = [ pkgs.unearth ];

  xdg.dataFile."vicinae/extensions/unearth".source = pkgs.unearth-vicinae;

  systemd.user.services.unearth-embed = {
    Unit = {
      Description = "EmbeddingGemma 2 server for unearth";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${lib.getExe pkgs.unearth} serve";
      Restart = "on-failure";
      # Indexing runs here too; keep it behind interactive work.
      Nice = 10;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  systemd.user.services.unearth-index = {
    Unit = {
      Description = "Index documents for unearth";
      Requires = [ "unearth-embed.service" ];
      After = [ "unearth-embed.service" ];
    };

    Service = {
      Type = "oneshot";
      ExecStart = lib.escapeShellArgs [
        (lib.getExe pkgs.unearth)
        "index"
        config.xdg.userDirs.documents
        config.xdg.userDirs.download
        config.xdg.userDirs.desktop
      ];
    };
  };

  systemd.user.timers.unearth-index = {
    Unit.Description = "Index documents for unearth hourly";
    Timer = {
      OnCalendar = "hourly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
