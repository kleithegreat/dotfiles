{ config, pkgs, ... }:

{
  systemd.user.services.sun-scheduler = {
    Unit.Description = "Calculate sunrise/sunset and schedule night-light events";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 ${config.home.homeDirectory}/repos/dotfiles/scripts/sun-schedule schedule";
    };
  };

  systemd.user.timers.sun-scheduler = {
    Unit.Description = "Daily sunrise/sunset scheduler";
    Timer = {
      OnStartupSec = "30";
      OnUnitActiveSec = "2h";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
