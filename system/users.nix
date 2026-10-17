{ config, lib, pkgs, ... }:

{
  programs.zsh.enable = true;

  users.users.kevin = {
    isNormalUser = true;
    uid = 1000;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "render"
      "i2c"
      "libvirtd"
      "lp"
    ];
    initialPassword = "changeme";
    shell = pkgs.zsh;
  };

  # Home Manager must finish before kevin's session starts, not before the greeter.
  systemd.services.home-manager-kevin.before =
    lib.mkForce [ "user@${toString config.users.users.kevin.uid}.service" ];

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
    };
  };

  # Remote dev servers (VS Code, Zed) push generic-linux binaries over SSH.
  programs.nix-ld.enable = config.services.openssh.enable;
}
