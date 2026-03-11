{ config, pkgs, dotfilesPath, hostName, ... }:

{
  imports = [
    ./shell.nix
    ./gtk.nix
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
    file           # file type identification
    unzip
    zip
    p7zip
    unrar

    # Network diagnostic tools
    nmap
    dnsutils       # provides dig, nslookup
    traceroute
    inetutils      # provides telnet, ftp, hostname, etc.

    # Editors
    neovim
    neovide

    # Neovim LSP servers (managed by Nix, not Mason)
    lua-language-server
    pyright
    texlab
    ltex-ls

    # Terminals
    alacritty
    ghostty
    tmux

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
    vscode
    imv            # Wayland image viewer
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.plasma-systemmonitor
    kdePackages.kate
    kdePackages.gwenview
    kdePackages.filelight
    kdePackages.kdeconnect-kde
    kdePackages.partitionmanager
    kdePackages.kcharselect
    kdePackages.isoimagewriter
    kdePackages.kompare
    tor-browser
    f3d            # 3D file viewer
    pavucontrol    # PulseAudio/PipeWire volume control GUI
    pkgs.gnome-secrets

    # 3D printing
    orca-slicer

    # Document tools
    pandoc

    # LaTeX (scheme-medium covers most packages including latexmk)
    texlive.combined.scheme-medium

    # Hyprland ecosystem
    hyprlock
    hypridle
    hyprpolkitagent

    # Desktop utilities
    swww
    brightnessctl
    grim
    slurp
    wl-clipboard
    playerctl
    easyeffects
    lsp-plugins    # audio plugins for EasyEffects
    networkmanager # provides nmcli for Quickshell

    quickshell
    fuzzel

    # Dev tools (lightweight baseline — heavy stuff goes in devshells)
    python3
    nodejs
    uv             # Python package/project manager

    # Theming / desktop integration
    libsecret      # Secret Service client (git credential helpers, etc.)

    # Man pages
    man-pages          # Linux man pages (sections 2-7)
    man-pages-posix    # POSIX man pages

    claude-code
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
  xdg.configFile."hypr/plugins.conf".text = ''
      plugin = ${pkgs.hyprlandPlugins.hyprbars}/lib/libhyprbars.so
      plugin = ${pkgs.hyprlandPlugins.hyprexpo}/lib/libhyprexpo.so

      plugin {
          hyprbars {
              bar_height = 24
              bar_color = rgb(3c3836)
              bar_text_color = rgb(ebdbb2)
              bar_font_family = Overpass
              bar_font_size = 10
              bar_buttons_alignment = left
              bar_button_padding = 8

              hyprbars-button = rgb(cc241d), 18, , hyprctl dispatch killactive
              hyprbars-button = rgb(d79921), 18, , hyprctl dispatch fullscreen 1
              hyprbars-button = rgb(689d6a), 18, , hyprctl dispatch movetoworkspacesilent special
          }

          hyprexpo {
              columns = 3
              gap_size = 5
              bg_col = rgb(282828)
              workspace_method = first 1
          }
      }
  '';

  # Host-specific — monitors and GPU env vars
  xdg.configFile."hypr/monitors.conf" = if hostName == "laptop"
    then { source = "${dotfilesPath}/hosts/laptop/monitors.conf"; }
    else { text = "monitor = ,preferred,auto,1\n"; };
  xdg.configFile."hypr/env.conf" = if hostName == "laptop"
    then { source = "${dotfilesPath}/config/hypr/env.conf"; }
    else { text = "env = XCURSOR_SIZE,24\n"; };

  # ── XDG Desktop Portal config ───────────────────────────────
  # Route file picker to KDE, everything else through Hyprland → GTK fallback
  xdg.configFile."xdg-desktop-portal/portals.conf".text = ''
    [preferred]
    default = hyprland;gtk
    org.freedesktop.impl.portal.FileChooser = kde
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

  # ── Git credential helper (uses gnome-keyring via libsecret) ──
  programs.git.settings.credential.helper =
    "${pkgs.gitFull}/bin/git-credential-libsecret";

  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}
