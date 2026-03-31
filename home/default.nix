{ config, pkgs, lib, dotfilesPath, hostName, hyprland, hyprland-plugins, vicinae, snappy-switcher, ... }:

let
  snappy-switcher-pkg = snappy-switcher.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  imports = [
    ./shell.nix
    ./gtk.nix
    vicinae.homeManagerModules.default
  ];

  home.username = "kevin";
  home.homeDirectory = "/home/kevin";

  # ── XDG ──────────────────────────────────────────────────────
  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      setSessionVariables = true;
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
    file           # file type identification
    unzip
    zip
    p7zip
    unrar
    psmisc
    rsync
    usbutils
    lm_sensors
    nvtopPackages.full

    # Network diagnostic tools
    nmap
    dnsutils       # provides dig, nslookup
    traceroute
    inetutils      # provides telnet, ftp, hostname, etc.
    iw
    netcat-openbsd

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
    slack
    thunderbird
    obs-studio
    libreoffice-fresh
    mpv
    spotify
    zathura
    vscode
    imv            # Wayland image viewer
    nautilus
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
    vlc
    zoom-us
    tor-browser
    f3d            # 3D file viewer
    anki
    gimp
    krita
    kdePackages.kdenlive
    kdePackages.krdc
    qbittorrent
    telegram-desktop
    pavucontrol    # PulseAudio/PipeWire volume control GUI
    pkgs.gnome-secrets

    # 3D printing
    orca-slicer

    # Document tools
    pandoc

    # `scheme-medium` pulls in `asymptote` via `collection-binextra`, which
    # currently recurses during evaluation on this nixpkgs revision.
    (texlive.withPackages (ps: with ps; [
      scheme-small
      latexmk
    ]))

    # Hyprland ecosystem
    hyprlock
    hypridle
    hyprpolkitagent
    hyprsunset
    geoclue2-with-demo-agent

    # Desktop utilities
    swww
    lutgen
    brightnessctl
    grim
    slurp
    wl-clipboard
    playerctl
    easyeffects
    lsp-plugins    # audio plugins for EasyEffects
    networkmanager # provides nmcli for Quickshell
    nwg-look       # GTK theme manager for Wayland

    quickshell
    snappy-switcher-pkg
    papirus-icon-theme
    rose-pine-cursor
    rose-pine-hyprcursor
    bibata-cursors

    # Dev tools (lightweight baseline — heavy stuff goes in devshells)
    python3
    nodejs
    uv             # Python package/project manager
    gh             # GitHub CLI

    # Theming / desktop integration
    libsecret      # Secret Service client (git credential helpers, etc.)
    kdePackages.qtstyleplugin-kvantum  # Kvantum Qt6 style engine
    libsForQt5.qtstyleplugin-kvantum   # Kvantum Qt5 style engine

    # Man pages
    man-pages          # Linux man pages (sections 2-7)
    man-pages-posix    # POSIX man pages

    claude-code
    codex
  ];

  # ── Hyprland configs ─────────────────────────────────────────
  # Shared configs from config/hypr/
  xdg.configFile."hypr/hyprland.conf".source = "${dotfilesPath}/config/hypr/hyprland.conf";
  xdg.configFile."hypr/appearance.conf".source = "${dotfilesPath}/config/hypr/appearance.conf";
  xdg.configFile."hypr/autostart.conf".source = "${dotfilesPath}/config/hypr/autostart.conf";
  xdg.configFile."hypr/input.conf".source = "${dotfilesPath}/config/hypr/input.conf";
  xdg.configFile."hypr/input-devices.conf" =
    if hostName == "laptop" then
      { source = "${dotfilesPath}/hosts/laptop/input-devices.conf"; }
    else if hostName == "desktop" then
      { source = "${dotfilesPath}/hosts/desktop/input-devices.conf"; }
    else
      { text = ""; };
  xdg.configFile."hypr/keybinds.conf".source = "${dotfilesPath}/config/hypr/keybinds.conf";
  xdg.configFile."hypr/rules.conf".source = "${dotfilesPath}/config/hypr/rules.conf";
  xdg.configFile."hypr/hypridle.conf".source = "${dotfilesPath}/config/hypr/hypridle.conf";
  xdg.configFile."hypr/hyprlock.conf".source = "${dotfilesPath}/config/hypr/hyprlock.conf";
  xdg.configFile."hypr/plugins.conf".source = "${dotfilesPath}/config/hypr/plugins.conf";

  # Host-specific — monitors and GPU env vars
  xdg.configFile."hypr/monitors.conf" =
    if hostName == "laptop" then
      { source = "${dotfilesPath}/hosts/laptop/monitors.conf"; }
    else if hostName == "desktop" then
      { source = "${dotfilesPath}/hosts/desktop/monitors.conf"; }
    else
      { text = "monitor = ,preferred,auto,1\n"; };
  xdg.configFile."hypr/env.conf" =
    if hostName == "laptop" then
      { source = "${dotfilesPath}/config/hypr/env.conf"; }
    else if hostName == "desktop" then
      { source = "${dotfilesPath}/hosts/desktop/env.conf"; }
    else
      { text = ""; };

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
  xdg.configFile."tmux/tmux.conf".source = "${dotfilesPath}/config/tmux/tmux.conf";
  xdg.configFile."git/ignore".source = "${dotfilesPath}/config/git/ignore";
  xdg.configFile."zathura/zathurarc".source = "${dotfilesPath}/config/zathura/zathurarc";
  # ── Snappy-switcher (alt-tab window switcher) ──────────────
  # config.ini is generated by apply-theme; only the packaged themes stay symlinked
  xdg.configFile."snappy-switcher/themes".source = "${snappy-switcher-pkg}/share/snappy-switcher/themes";

  # ── WirePlumber Bluetooth codecs ─────────────────────────────
  xdg.configFile."wireplumber/wireplumber.conf.d/50-bluetooth.conf".text = ''
    monitor.bluez.properties = {
      bluez5.enable-sbc-xq = true
      bluez5.enable-msbc = true
      bluez5.enable-hw-volume = true
    }
  '';

  # ── Git credential helper (uses gnome-keyring via libsecret) ──
  programs.git.settings.credential.helper =
    "${pkgs.gitFull}/bin/git-credential-libsecret";

  # ── Scripts ──────────────────────────────────────────────────
  home.file.".local/bin/dim-screen.sh" = {
    source = "${dotfilesPath}/scripts/dim-screen.sh";
    executable = true;
  };
  home.file.".local/bin/brightness-step.sh" = {
    source = "${dotfilesPath}/scripts/brightness-step.sh";
    executable = true;
  };
  home.file.".local/bin/toggle-float.sh" = {
    source = "${dotfilesPath}/scripts/toggle-float.sh";
    executable = true;
  };

  # ── Desktop entry overrides ───────────────────────────────
  # Launch VS Code via hyprctl so Hyprland tracks the correct workspace
  xdg.desktopEntries.code = {
    name = "Visual Studio Code";
    comment = "Code Editing. Redefined.";
    genericName = "Text Editor";
    icon = "vscode";
    exec = "hyprctl dispatch exec code %F";
    categories = ["Utility" "TextEditor" "Development" "IDE"];
    startupNotify = true;
    settings = {
      Keywords = "vscode";
      StartupWMClass = "Code";
      Version = "1.5";
    };
    actions = {
      new-empty-window = {
        name = "New Empty Window";
        icon = "vscode";
        exec = "hyprctl dispatch exec -- code --new-window %F";
      };
    };
  };

  # ── Default applications ────────────────────────────────────
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "chromium.desktop";
      "x-scheme-handler/http" = "chromium.desktop";
      "x-scheme-handler/https" = "chromium.desktop";
      "application/pdf" = "org.pwmt.zathura.desktop";
      "inode/directory" = "org.kde.dolphin.desktop";
      "image/png" = "imv.desktop";
      "image/jpeg" = "imv.desktop";
      "image/jpg" = "imv.desktop";
      "image/gif" = "imv.desktop";
      "image/webp" = "imv.desktop";
      "image/svg+xml" = "imv.desktop";
      "video/mp4" = "vlc.desktop";
      "video/x-matroska" = "vlc.desktop";
      "video/x-msvideo" = "vlc.desktop";
      "video/webm" = "vlc.desktop";
      "text/plain" = "neovide.desktop";
      "x-scheme-handler/mailto" = "thunderbird.desktop";
      "x-scheme-handler/terminal" = "Alacritty.desktop";
    };
  };

  # ── Vicinae (app launcher) ──────────────────────────────────
  services.vicinae.enable = true;

  # ── Theme activation ────────────────────────────────────────
  home.activation.applyTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PATH="${lib.makeBinPath [pkgs.python3]}:$PATH"
    ${dotfilesPath}/themes/apply-theme sync
  '';

  # ── Chromium ───────────────────────────────────────────────
  programs.chromium = {
    enable = true;
    extensions = [
      "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
      "nngceckbapebfimnlniiiahkandclblb"  # Bitwarden
      "nkbihfbeogaeaoehlefnkodbefgpgknn"  # MetaMask
      "bfnaelmomeimhlpmgjnjophhpkkoljpa"  # Phantom
    ];
  };

  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}
