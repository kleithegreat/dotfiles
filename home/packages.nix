{ pkgs, ... }:

let
  texlive = pkgs.texlive.withPackages (ps: with ps; [
    scheme-small
    latexmk
    tikz-cd
    titlesec
    tocloft
    enumitem
    mdframed
    needspace
    zref
    algorithms
    cleveref
    eepic
    libertine
    paralist
    wrapfig
  ]);

  customPackages = [
    pkgs.opencode
    pkgs.optimized.fd
    pkgs.optimized.ripgrep
    pkgs.optimized.desktopctl
    pkgs.optimized.p7zip
    texlive
    pkgs.optimized.lsp-plugins
    pkgs.optimized.quickshell
    pkgs.snappy-switcher
    pkgs.macos-vm
    pkgs.vicinae
  ];

  discordKrispSrc = pkgs.fetchurl {
    inherit (pkgs.discord.source.modules.discord_krisp) url hash;
  };

  discordKrispPatcherPython = pkgs.python3.withPackages (ps: [ ps.lief ]);

  discordPatchedKrisp = pkgs.runCommand "discord-krisp-patched" {
    nativeBuildInputs = [ pkgs.brotli ];
  } ''
    mkdir --parents "$out"
    brotli -d < ${discordKrispSrc} | tar xf - --strip-components=1 -C "$out"
    ${discordKrispPatcherPython}/bin/python3 ${../pkgs/discord-krisp/patch-linux.py} "$out"
  '';

  discordKrispDeployPython = pkgs.python3.withPackages (ps: [ ps.watchdog ]);

  discordPkg = pkgs.discord.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ pkgs.python3 ];
    postInstall = (old.postInstall or "") + ''
      rm --recursive --force "$out/opt/Discord/modules/discord_krisp"
      mkdir --parents "$out/opt/Discord/modules/discord_krisp"
      cp --recursive ${discordPatchedKrisp}/. "$out/opt/Discord/modules/discord_krisp/"
      chmod --recursive u+w "$out/opt/Discord/modules/discord_krisp"

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

      rm --force "$out/bin/Discord" "$out/bin/discord"
      install -Dm0755 /dev/stdin "$out/bin/Discord" <<EOF
      #!${pkgs.runtimeShell}
      "$out/bin/.discord-deploy-krisp"
      exec "$out/opt/Discord/Discord" "\$@"
      EOF
      ln --symbolic "$out/bin/Discord" "$out/bin/discord" || true
    '';
    passthru = (old.passthru or {}) // {
      patchedKrisp = discordPatchedKrisp;
    };
  });

  basePackages = with pkgs; [
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
    libreoffice
    vscode
    zed-editor
    lmstudio
    comfyui
    helium
    imv
    nautilus
    glib
    gdk-pixbuf
    gedit
    haruna
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
    t3code
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
