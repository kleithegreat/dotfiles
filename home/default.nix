{ config, pkgs, ... }:

{
  home.username = "kevin";
  home.homeDirectory = "/home/kevin";

  # Zsh as default shell
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Starship prompt
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  # CLI tools
  home.packages = with pkgs; [
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

  # Zoxide
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # fzf shell integration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # bat
  programs.bat = {
    enable = true;
  };

  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}