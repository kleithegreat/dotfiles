{ config, pkgs, dotfilesPath, ... }:

{
  imports = [
    ./shell.nix
  ];

  home.username = "kevin";
  home.homeDirectory = "/home/kevin";

  # ── XDG ──────────────────────────────────────────────────────
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      createDirectories = true;
      desktop = "${config.home.homeDirectory}/Desktop";
      documents = "${config.home.homeDirectory}/Documents";
      download = "${config.home.homeDirectory}/Downloads";
      music = "${config.home.homeDirectory}/Music";
      pictures = "${config.home.homeDirectory}/Pictures";
      videos = "${config.home.homeDirectory}/Videos";
    };
  };

  # ── Packages ─────────────────────────────────────────────────
  home.packages = with pkgs; [
    # CLI tools
    bat
    eza
    fd
    ripgrep
    fzf
    jq
    tree
    ncdu
    htop
    strace
    bc
    less
    fastfetch
    wget
    curl

    # Terminals
    alacritty
    ghostty

    # GUI apps
    discord
    obsidian
    chromium
    slack
    thunderbird
    obs-studio
    libreoffice-fresh
    mpv
    spotify
    zathura
    kdePackages.dolphin
  ];

  # ── Hyprland configs ─────────────────────────────────────────
  # Shared configs from config/hypr/
  xdg.configFile."hypr/hyprland.conf".source = "${dotfilesPath}/config/hypr/hyprland.conf";
  xdg.configFile."hypr/appearance.conf".source = "${dotfilesPath}/config/hypr/appearance.conf";
  xdg.configFile."hypr/autostart.conf".source = "${dotfilesPath}/config/hypr/autostart.conf";
  xdg.configFile."hypr/colors.conf".source = "${dotfilesPath}/config/hypr/colors.conf";
  xdg.configFile."hypr/input.conf".source = "${dotfilesPath}/config/hypr/input.conf";
  xdg.configFile."hypr/keybinds.conf".source = "${dotfilesPath}/config/hypr/keybinds.conf";
  xdg.configFile."hypr/rules.conf".source = "${dotfilesPath}/config/hypr/rules.conf";
  xdg.configFile."hypr/hypridle.conf".source = "${dotfilesPath}/config/hypr/hypridle.conf";
  xdg.configFile."hypr/hyprlock.conf".source = "${dotfilesPath}/config/hypr/hyprlock.conf";

  # Host-specific — VM defaults (overridden per-host later)
  xdg.configFile."hypr/monitors.conf".text = ''
    monitor = ,preferred,auto,1
  '';
  xdg.configFile."hypr/env.conf".text = ''
    env = XCURSOR_SIZE,24
  '';

  # ── Other app configs ────────────────────────────────────────
  xdg.configFile."quickshell" = {
    source = "${dotfilesPath}/config/quickshell";
    recursive = true;
  };

  xdg.configFile."nvim" = {
    source = "${dotfilesPath}/config/nvim";
    recursive = true;
  };

  xdg.configFile."alacritty/alacritty.toml".source = "${dotfilesPath}/config/alacritty/alacritty.toml";
  xdg.configFile."ghostty/config".source = "${dotfilesPath}/config/ghostty/config";
  xdg.configFile."starship.toml".source = "${dotfilesPath}/config/starship/starship.toml";
  xdg.configFile."tmux/tmux.conf".source = "${dotfilesPath}/config/tmux/tmux.conf";
  xdg.configFile."git/ignore".source = "${dotfilesPath}/config/git/ignore";
  xdg.configFile."zathura/zathurarc".source = "${dotfilesPath}/config/zathura/zathurarc";
  xdg.configFile."vicinae" = {
    source = "${dotfilesPath}/config/vicinae";
    recursive = true;
  };

  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}