{ pkgs, desktopctl, fd, p7zip, quickshell, ripgrep, lspPlugins, opencodePkg, harunaPkg, snappySwitcherPkg, vicinaePkg, texlive }:

let
  customPackages = [
    opencodePkg
    fd
    ripgrep
    desktopctl
    p7zip
    texlive
    lspPlugins
    quickshell
    snappySwitcherPkg
    vicinaePkg
  ];

  discordKrispSrc = pkgs.fetchurl {
    inherit (pkgs.discord.source.modules.discord_krisp) url hash;
  };

  discordKrispPatcherPython = pkgs.python3.withPackages (ps: [ ps.lief ]);

  discordPatchedKrisp = pkgs.runCommand "discord-krisp-patched" {
    nativeBuildInputs = [ pkgs.brotli ];
  } ''
    mkdir -p "$out"
    brotli -d < ${discordKrispSrc} | tar xf - --strip-components=1 -C "$out"
    ${discordKrispPatcherPython}/bin/python3 ${../pkgs/discord-krisp/patch-linux.py} "$out"
  '';

  discordKrispDeployPython = pkgs.python3.withPackages (ps: [ ps.watchdog ]);

  discordPkg = pkgs.discord.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.python3 ];
    postInstall = (old.postInstall or "") + ''
      rm -rf "$out/opt/Discord/modules/discord_krisp"
      mkdir -p "$out/opt/Discord/modules/discord_krisp"
      cp -R ${discordPatchedKrisp}/. "$out/opt/Discord/modules/discord_krisp/"
      chmod -R u+w "$out/opt/Discord/modules/discord_krisp"

      python3 ${../pkgs/discord-krisp/patch-voice.py} \
        "$out/opt/Discord/modules/discord_voice/index.js" \
        "require('path').join(process.env.XDG_CONFIG_HOME || require('path').join(require('os').homedir(), '.config'), 'discord', '${old.version}', 'modules', 'discord_krisp')" \
        "$out/opt/Discord/resources/build_info.json" \
        "$out/opt/Discord/modules"

      install -Dm0755 ${../pkgs/discord-krisp/deploy.py} "$out/bin/.discord-deploy-krisp"
      substituteInPlace "$out/bin/.discord-deploy-krisp" \
        --replace-fail '@pythonInterpreter@' '${discordKrispDeployPython}/bin/python3' \
        --replace-fail '@krispPath@' "$out/opt/Discord/modules/discord_krisp" \
        --replace-fail '@discordVersion@' '${old.version}' \
        --replace-fail '@configDirName@' 'discord'

      rm -f "$out/bin/Discord" "$out/bin/discord"
      install -Dm0755 /dev/stdin "$out/bin/Discord" <<EOF
      #!${pkgs.runtimeShell}
      "$out/bin/.discord-deploy-krisp"
      exec "$out/opt/Discord/Discord" "\$@"
      EOF
      ln -s "$out/bin/Discord" "$out/bin/discord" || true
    '';
    passthru = (old.passthru or {}) // {
      patchedKrisp = discordPatchedKrisp;
    };
  });

  basePackages = with pkgs; [
    openchamber
    bat
    eza
    fzf
    jq
    tree
    ncdu
    htop
    strace
    bc
    less
    file
    unzip
    zip
    unrar
    psmisc
    rsync
    usbutils
    lm_sensors
    nvtopPackages.full
    nmap
    dnsutils
    traceroute
    inetutils
    iw
    netcat-openbsd
    mission-center
    neovim
    gcc # nvim treesitter parser compilation (:TSUpdate / ensure_installed)
    neovide
    lua-language-server
    pyright
    texlab
    ltex-ls
    alacritty
    ghostty
    tmux
    discordPkg
    obsidian
    slack
    thunderbird
    obs-studio
    spotify
    zathura
    vscode
    zed-editor
    lmstudio
    helium
    imv
    nautilus
    glib
    gdk-pixbuf
    gedit
    harunaPkg
    ffmpeg
    zoom-us
    tor-browser
    winboat
    freerdp
    podman-compose
    fstl
    anki
    gimp
    krita
    prismlauncher
    qbittorrent
    telegram-desktop
    pavucontrol
    gnome-secrets
    bambu-studio
    pandoc
    hypridle
    hyprpolkitagent
    hyprsunset
    geoclue2-with-demo-agent
    awww
    lutgen
    brightnessctl
    ddcutil
    grim
    slurp
    wl-clipboard
    playerctl
    easyeffects
    networkmanager
    nwg-look
    papirus-icon-theme
    rose-pine-cursor
    rose-pine-hyprcursor
    bibata-cursors
    python3
    nodejs
    qt6.qtdeclarative
    uv
    gh
    libsecret
    man-pages
    man-pages-posix
    claude-code
    codex
  ];

  kdePackages = with pkgs.kdePackages; [
    dolphin
    ark
    kate
    gwenview
    kimageformats
    filelight
    kdeconnect-kde
    kcharselect
    isoimagewriter
    kompare
    kdenlive
    krdc
  ];
in
{
  home.packages = customPackages ++ basePackages ++ kdePackages;

}
