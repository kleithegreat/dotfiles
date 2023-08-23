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

  fileSystems."/mnt/windows" = {
    device = "/dev/nvme1n1p3";
    fsType = "ntfs-3g"; # Use the ntfs-3g driver
    options = [ "rw" "umask=0007" "uid=1000" "gid=100" ];
  };

  # Installed System Packages
  environment.systemPackages = let
  unstable = import <nixos-unstable> {};
  in with pkgs; [
    pkgs.alacritty
    pkgs.brightnessctl
    pkgs.btop
    pkgs.discord
    pkgs.dunst
    pkgs.eww-wayland
    pkgs.exa
    pkgs.file
    pkgs.firefox
    pkgs.fish
    pkgs.gcc
    pkgs.git
    pkgs.gnome.gnome-keyring
    pkgs.gnumake
    pkgs.gparted
    pkgs.gucharmap
    pkgs.htop
    pkgs.hyprpaper
    pkgs.kitty
    pkgs.lxqt.lxqt-policykit
    pkgs.neofetch
    pkgs.neovim
    pkgs.nerdfix
    pkgs.nerdfonts
    pkgs.ntfs3g
    pkgs.obsidian
    pkgs.pandoc
    pkgs.pciutils
    pkgs.pcmanfm
    pkgs.pipewire
    pkgs.playerctl
    pkgs.psmisc
    pkgs.pulseaudio
    (python310.withPackages (ps: [
    	ps.pip
	    ps.jupyter
    	ps.numpy
    	ps.pandas
    	ps.matplotlib
    	ps.requests
    	ps.beautifulsoup4
    ]))
    pkgs.qt6.qtwayland
    pkgs.R
    pkgs.rstudio
    pkgs.rofi-wayland
    pkgs.rustup
    pkgs.spotify
    pkgs.starship
    pkgs.swayidle
    pkgs.swaylock-effects
    pkgs.unrar
    pkgs.ungoogled-chromium
    pkgs.unzip
    pkgs.vim
    pkgs.vlc
    pkgs.vscode
    pkgs.wireplumber
    pkgs.wget
    pkgs.zip
    pkgs.zathura
    unstable.waybar-hyprland
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
