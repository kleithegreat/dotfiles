{ config, pkgs, ... }:

{
  # Imports and Basic System Settings
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "nixos";
  time.timeZone = "America/Chicago";
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
    packages = with pkgs; [
      vim # move vim from system packages to user packages
    ];
  };

  # Allow Unfree Packages
  nixpkgs.config.allowUnfree = true;

  # File System Settings
  fileSystems."/mnt/windows" = {
    device = "/dev/nvme1n1p3";
    fsType = "ntfs-3g"; # Use the ntfs-3g driver
    options = [ "rw" "umask=0007" "uid=1000" "gid=100" ];
  };

  # Installed System Packages
  environment.systemPackages = let
    unstable = import <nixos-unstable> {};
  in with pkgs; [
    alacritty
    brightnessctl
    btop
    catppuccin-gtk
    clang
    dconf
    discord
    dunst
    eww-wayland
    exa
    file
    firefox
    fish
    gcc
    git
    glib
    gnome.gnome-keyring
    gnome.gnome-settings-daemon43
    gnome.gnome-tweaks
    gnumake
    gparted
    gtk2
    gtk3
    gtk4
    gucharmap
    htop
    hyprpaper
    kitty
    libsecret
    libreoffice
    lxappearance
    lxqt.lxqt-policykit
    neofetch
    neovim
    nerdfix
    nerdfonts
    nodejs
    ntfs3g
    nvtop
    obsidian
    pandoc
    pciutils
    pcmanfm
    pipewire
    playerctl
    psmisc
    (python310.withPackages (ps: [
      ps.pip
      ps.jupyter
      ps.numpy
      ps.pandas
      ps.matplotlib
      ps.requests
      ps.beautifulsoup4
    ]))
    qt6.qtwayland
    R
    rstudio
    rofi-wayland
    rustdesk
    rustup
    spotify
    starship
    swayidle
    swaylock-effects
    texlive.combined.scheme-full
    unrar
    ungoogled-chromium
    unzip
    vim
    vlc
    vscode-fhs
    wireplumber
    wget
    zip
    zathura
    unstable.waybar
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

  services.dbus.enable = true;
  services.dbus.packages = [ pkgs.gnome3.gnome-keyring ];

  nix.extraOptions = "experimental-features = nix-command flakes";

  # Waybar Overlay
  nixpkgs.overlays = [
    (self: super: {
      waybar = super.waybar.overrideAttrs (oldAttrs: {
        mesonFlags = oldAttrs.mesonFlags ++ [ "-Dexperimental=true" ];
      });
    })
  ];
}

