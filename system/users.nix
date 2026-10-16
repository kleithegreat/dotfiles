{ config, pkgs, ... }:

{
  programs.zsh.enable = true;

  users.users.kevin = {
    isNormalUser = true;
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
