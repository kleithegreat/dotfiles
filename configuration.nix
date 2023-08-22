{ config, pkgs, ... }:

{
  # Imports and Basic System Settings
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "nixos";
  time.timeZone = "America/New_York";
  i18n.defaultLocale = "en_US.UTF-8";
  system.stateVersion = "23.05";

  # Bootloader Settings
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = false;
    device = "nodev";
  };

  # Networking Settings
  networking = {
    networkmanager.enable = true;
    # Uncomment for proxy settings
    # proxy.default = "http://user:password@proxy:port/";
    # proxy.noProxy = "127.0.0.1,localhost,internal.domain";
  };

  # Locale Settings
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  # Display and XServer Settings
  services.xserver = {
    enable = true;
    layout = "us";
    xkbVariant = "";
    videoDrivers = [ "nvidia" ];
    displayManager.gdm = {
      enable = true;
      wayland = true;
    };
  };

  # User Account Settings
  users.users.kevin = {
    shell = pkgs.fish;
    isNormalUser = true;
    description = "kevin";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [];
  };

  # Packages and Overlays
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      (self: super: {
        waybar = super.waybar.overrideAttrs (oldAttrs: {
          mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
        });
      })
    ];
  };

  # Installed System Packages
  environment.systemPackages = let
    unstable = import <nixos-unstable> {};
  in with pkgs; [
    pkgs.alacritty
    pkgs.git
    pkgs.wget
    pkgs.vim
    pkgs.firefox
    pkgs.ungoogled-chromium
    pkgs.neovim
    pkgs.neofetch
    pkgs.kitty
    pkgs.hyprpaper
    pkgs.eww-wayland
    unstable.waybar-hyprland
    pkgs.htop
    pkgs.btop
    pkgs.swaylock-effects
    pkgs.swayidle
    pkgs.rofi-wayland
    pkgs.fish
    pkgs.vscode
    pkgs.brightnessctl
    pkgs.exa
    pkgs.nerdfonts
    pkgs.nerdfix
    pkgs.starship
    pkgs.pulseaudio
    pkgs.playerctl
    pkgs.discord
    pkgs.rustup
    pkgs.pcmanfm
    pkgs.gnumake
    pkgs.spotify
    pkgs.unrar
    pkgs.zip
    pkgs.unzip
    pkgs.gcc
    pkgs.gnome.gnome-keyring
    pkgs.gparted
    pkgs.psmisc
    pkgs.gucharmap
    pkgs.pandoc
    pkgs.zathura
    pkgs.vlc
    pkgs.file
    pkgs.lxqt.lxqt-policykit
  ];

  # Miscellaneous Settings
  hardware = {
    opengl.enable = true;
    nvidia.modesetting.enable = true;
  };

  programs = {
    hyprland = {
      enable = true;
      xwayland.enable = true;
      nvidiaPatches = true;
    };
    fish.enable = true;
  };

  fonts.fonts = with pkgs; [ nerdfonts ];

  hardware.pulseaudio = {
    enable = true;
    systemWide = false;
  };

  security.pam.services.swaylock = {};

  services.dbus.packages = [ pkgs.gnome3.gnome-keyring ];
}
