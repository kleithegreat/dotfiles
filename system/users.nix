{ pkgs, ... }:

{
  programs.zsh.enable = true;

  users.users.kevin = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "render"
      "docker"
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
}
