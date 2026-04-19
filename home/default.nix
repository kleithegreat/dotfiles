{ config, pkgs, lib, dotfilesPath, hostName, vicinae, snappy-switcher, opencode, enableNativeOptimizations, ... }:

let
  nativeOptimizations = import ../system/native-optimizations.nix {
    inherit lib hostName enableNativeOptimizations;
  };
  stockPkgs = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
  };
  opencode-pkg = nativeOptimizations.optimizeNativePackage (opencode.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    postConfigure = (old.postConfigure or "") + ''
      if [ -e packages/app/node_modules/@tsconfig/bun/tsconfig.json ]; then
        substituteInPlace packages/shared/tsconfig.json \
          --replace-fail '"extends": "@tsconfig/bun/tsconfig.json"' '"extends": "../app/node_modules/@tsconfig/bun/tsconfig.json"'
      fi

      if [ ! -e node_modules/prettier/package.json ]; then
        for prettier in node_modules/.bun/prettier@*/node_modules/prettier; do
          if [ -e "$prettier/package.json" ]; then
            chmod u+w node_modules
            ln -s "$PWD/$prettier" node_modules/prettier
            break
          fi
        done
      fi

      if [ ! -e node_modules/glob/package.json ] && [ -e packages/opencode/node_modules/glob/package.json ]; then
        chmod u+w node_modules
        ln -s "$PWD/packages/opencode/node_modules/glob" node_modules/glob
      fi
    '';
  }));
  snappy-switcher-pkg = nativeOptimizations.optimizeNativePackage (snappy-switcher.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      ../patches/snappy-switcher/workspace-scope-filter.patch
    ];
  }));
  vicinae-pkg = nativeOptimizations.optimizeNativePackage vicinae.packages.${pkgs.stdenv.hostPlatform.system}.default;
  # Keep codex on stock nixpkgs so the native ripgrep overlay does not change
  # its wrapped PATH and force a host-local rebuild.
  codex-pkg = stockPkgs.codex;
  lapce-pkg = pkgs.lapce;
  ableton-prefix = "${config.home.homeDirectory}/.local/share/wineprefixes/ableton-live-12-lite";
  ableton-launcher = pkgs.writeShellApplication {
    name = "ableton-live-12-lite";
    text = ''
      export WINEPREFIX="${ableton-prefix}"
      export WINEDLLOVERRIDES="winepulse.drv=d;winex11.drv=d"

      exe='C:\ProgramData\Ableton\Live 12 Lite\Program\Ableton Live 12 Lite.exe'

      if [ "$#" -eq 0 ]; then
        exec ${pkgs.pipewire.jack}/bin/pw-jack \
          ${pkgs.wineWow64Packages.stableFull}/bin/wine \
          "$exe"
      fi

      converted_args=()
      for arg in "$@"; do
        if [ -e "$arg" ]; then
          converted_args+=("$(${pkgs.wineWow64Packages.stableFull}/bin/winepath -w "$arg")")
        else
          converted_args+=("$arg")
        fi
      done

      exec ${pkgs.pipewire.jack}/bin/pw-jack \
        ${pkgs.wineWow64Packages.stableFull}/bin/wine \
        "$exe" \
        "''${converted_args[@]}"
    '';
  };
  ableton-launcher-x11 = pkgs.writeShellApplication {
    name = "ableton-live-12-lite-x11";
    text = ''
      export WINEPREFIX="${ableton-prefix}"
      export WINEDLLOVERRIDES="winepulse.drv=d;winewayland.drv=d"

      exe='C:\ProgramData\Ableton\Live 12 Lite\Program\Ableton Live 12 Lite.exe'

      if [ "$#" -eq 0 ]; then
        exec ${pkgs.pipewire.jack}/bin/pw-jack \
          ${pkgs.wineWow64Packages.stableFull}/bin/wine \
          "$exe"
      fi

      converted_args=()
      for arg in "$@"; do
        if [ -e "$arg" ]; then
          converted_args+=("$(${pkgs.wineWow64Packages.stableFull}/bin/winepath -w "$arg")")
        else
          converted_args+=("$arg")
        fi
      done

      exec ${pkgs.pipewire.jack}/bin/pw-jack \
        ${pkgs.wineWow64Packages.stableFull}/bin/wine \
        "$exe" \
        "''${converted_args[@]}"
    '';
  };
  ableton-launcher-x11-desktop = pkgs.writeShellApplication {
    name = "ableton-live-12-lite-x11-desktop";
    text = ''
      export WINEPREFIX="${ableton-prefix}"
      export WINEDLLOVERRIDES="winepulse.drv=d;winewayland.drv=d"

      exe='C:\ProgramData\Ableton\Live 12 Lite\Program\Ableton Live 12 Lite.exe'
      desktop='Ableton,1600x900'

      if [ "$#" -eq 0 ]; then
        exec ${pkgs.pipewire.jack}/bin/pw-jack \
          ${pkgs.wineWow64Packages.stableFull}/bin/wine \
          explorer /desktop="$desktop" \
          "$exe"
      fi

      converted_args=()
      for arg in "$@"; do
        if [ -e "$arg" ]; then
          converted_args+=("$(${pkgs.wineWow64Packages.stableFull}/bin/winepath -w "$arg")")
        else
          converted_args+=("$arg")
        fi
      done

      exec ${pkgs.pipewire.jack}/bin/pw-jack \
        ${pkgs.wineWow64Packages.stableFull}/bin/wine \
        explorer /desktop="$desktop" \
        "$exe" \
        "''${converted_args[@]}"
    '';
  };
in
{
  imports = [
    ./shell.nix
    ./gtk.nix
    ./fastfetch.nix
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
    opencode-pkg
    openchamber
    bat
    eza
    fd
    ripgrep
    fzf
    jq
    tree
    ncdu
    htop
    desktopctl
    strace
    bc
    less
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
    spotify
    zathura
    vscode
    lapce-pkg
    lmstudio
    helium
    imv            # Wayland image viewer
    nautilus
    kdePackages.dolphin
    kdePackages.ark
    kdePackages.plasma-systemmonitor
    gedit
    kdePackages.kate
    kdePackages.gwenview
    kdePackages.filelight
    kdePackages.kdeconnect-kde
    kdePackages.kcharselect
    kdePackages.isoimagewriter
    kdePackages.kompare
    haruna
    zoom-us
    tor-browser
    f3d            # 3D file viewer
    anki
    gimp
    krita
    kdePackages.kdenlive
    kdePackages.krdc
    prismlauncher
    qbittorrent
    telegram-desktop
    pavucontrol    # PulseAudio/PipeWire volume control GUI
    pkgs.gnome-secrets
    # KDE Partition Manager is enabled in system/configuration.nix via
    # programs.partition-manager so kpmcore's D-Bus service and polkit action
    # are registered system-wide.
    # bitwarden-desktop is in environment.systemPackages (system/configuration.nix)
    # so its polkit policy file gets linked into the system-wide polkit actions dir.
    # Home Manager doesn't do this, which breaks "Unlock with system authentication".

    # 3D printing
    orca-slicer

    # Document tools
    pandoc

    # `scheme-medium` pulls in `asymptote` via `collection-binextra`, which
    # currently recurses during evaluation on this nixpkgs revision.
    (texlive.withPackages (ps: with ps; [
      scheme-small
      latexmk
      tikz-cd
      titlesec
      tocloft
      enumitem
      mdframed
      needspace
      zref
    ]))

    # Hyprland ecosystem
    hypridle
    hyprpolkitagent
    hyprsunset
    geoclue2-with-demo-agent

    # Desktop utilities
    awww
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
    qt6.qtdeclarative # qmllint for Quickshell QML configs
    uv             # Python package/project manager
    gh             # GitHub CLI

    # Theming / desktop integration
    libsecret      # Secret Service client (git credential helpers, etc.)

    # Man pages
    man-pages          # Linux man pages (sections 2-7)
    man-pages-posix    # POSIX man pages

    claude-code
    codex-pkg
  ] ++ lib.optionals (hostName == "desktop") [
    ableton-launcher
    ableton-launcher-x11
    ableton-launcher-x11-desktop
  ];

  # ── Hyprland configs ─────────────────────────────────────────
  # Shared configs from config/hypr/
  xdg.configFile."hypr/hyprland.conf".source = "${dotfilesPath}/config/hypr/hyprland.conf";
  xdg.configFile."hypr/appearance.conf".source = "${dotfilesPath}/config/hypr/appearance.conf";
  xdg.configFile."hypr/autostart.conf".source = "${dotfilesPath}/config/hypr/autostart.conf";
  xdg.configFile."hypr/autostart-host.conf" =
    if hostName == "desktop" then
      { source = "${dotfilesPath}/hosts/desktop/autostart.conf"; }
    else
      { text = ""; };
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
  # config.ini is generated by desktopctl; only the packaged themes stay symlinked
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

  xdg.dataFile = lib.optionalAttrs (hostName == "desktop") {
    "applications/wine/Programs/Ableton Live 12 Lite.desktop".text = ''
      [Desktop Entry]
      Name=Ableton Live 12 Lite
      Exec=${ableton-launcher}/bin/ableton-live-12-lite %F
      Type=Application
      StartupNotify=true
      Path=${ableton-prefix}/drive_c/ProgramData/Ableton/Live 12 Lite/Program
      Icon=7D21_Ableton Live 12 Lite.0
      StartupWMClass=ableton live 12 lite.exe
      Categories=AudioVideo;Audio;Music;
    '';
    "applications/ableton-live-12-lite-x11.desktop".text = ''
      [Desktop Entry]
      Name=Ableton Live 12 Lite (XWayland)
      Exec=${ableton-launcher-x11}/bin/ableton-live-12-lite-x11 %F
      Type=Application
      StartupNotify=true
      Path=${ableton-prefix}/drive_c/ProgramData/Ableton/Live 12 Lite/Program
      Icon=7D21_Ableton Live 12 Lite.0
      StartupWMClass=ableton live 12 lite.exe
      Categories=AudioVideo;Audio;Music;
    '';
    "applications/ableton-live-12-lite-x11-desktop.desktop".text = ''
      [Desktop Entry]
      Name=Ableton Live 12 Lite (XWayland Desktop)
      Exec=${ableton-launcher-x11-desktop}/bin/ableton-live-12-lite-x11-desktop %F
      Type=Application
      StartupNotify=true
      Path=${ableton-prefix}/drive_c/ProgramData/Ableton/Live 12 Lite/Program
      Icon=7D21_Ableton Live 12 Lite.0
      StartupWMClass=explorer.exe
      Categories=AudioVideo;Audio;Music;
    '';
  };

  # ── Default applications ────────────────────────────────────
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "chromium-browser.desktop";
      "x-scheme-handler/http" = "chromium-browser.desktop";
      "x-scheme-handler/https" = "chromium-browser.desktop";
      "application/pdf" = "chromium-browser.desktop";
      "inode/directory" = "org.gnome.Nautilus.desktop";
      "image/png" = "imv.desktop";
      "image/jpeg" = "imv.desktop";
      "image/jpg" = "imv.desktop";
      "image/gif" = "imv.desktop";
      "image/webp" = "imv.desktop";
      "image/svg+xml" = "imv.desktop";
      "video/mp4" = "org.kde.haruna.desktop";
      "video/x-matroska" = "org.kde.haruna.desktop";
      "video/x-msvideo" = "org.kde.haruna.desktop";
      "video/webm" = "org.kde.haruna.desktop";
      "text/plain" = "org.gnome.gedit.desktop";
      "x-scheme-handler/mailto" = "thunderbird.desktop";
      "x-scheme-handler/terminal" = "Alacritty.desktop";
    };
  };

  # ── Vicinae (app launcher) ──────────────────────────────────
  services.vicinae = {
    enable = true;
    package = vicinae-pkg;
  };

  # ── Theme activation ────────────────────────────────────────
  home.activation.applyTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
    PATH="${lib.makeBinPath [pkgs.desktopctl]}:$PATH"
    mkdir -p "$HOME/.config/hypr"
    touch "$HOME/.config/hypr/input-runtime.conf"
    touch "$HOME/.config/hypr/animations-override.conf"
    touch "$HOME/.config/hypr/keybinds-override.conf"
    desktopctl theme sync
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
