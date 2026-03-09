{ config, pkgs, ... }:

{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nixpkgs.config.allowUnfree = true;

  # Networking
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  # Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # hyprlock — also auto-creates security.pam.services.hyprlock
  programs.hyprlock.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    overpass
  ];

  # Electron apps: use Wayland backend
  environment.sessionVariables.NIXOS_OZONE_WL = "1";

  # Portals
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-hyprland
      xdg-desktop-portal-gtk
    ];
  };

  # Display manager
  services.displayManager.sddm = {
    enable = true;
    wayland.enable = true;
  };

  # Audio (Hyprland expects PipeWire)
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
  };
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;

  # Locale
  time.timeZone = "America/Chicago";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS        = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT    = "en_US.UTF-8";
    LC_MONETARY       = "en_US.UTF-8";
    LC_NAME           = "en_US.UTF-8";
    LC_NUMERIC        = "en_US.UTF-8";
    LC_PAPER          = "en_US.UTF-8";
    LC_TELEPHONE      = "en_US.UTF-8";
    LC_TIME           = "en_US.UTF-8";
  };
  console.keyMap = "us";

  programs.zsh.enable = true;

  # User
  users.users.kevin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "changeme";
    shell = pkgs.zsh;
  };

  # SSH — so we can paste from host
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  # Bare minimum packages
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
  ];

  system.stateVersion = "25.05";
}
