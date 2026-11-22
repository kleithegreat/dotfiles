{ pkgs, ... }:

{
  programs.spicetify.enable = true;

  home.packages = with pkgs; [
    opencode
    optimized.fd
    optimized.ripgrep
    optimized.desktopctl
    optimized.p7zip
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
      algorithm2e
      # algorithm2e loads these; its tlpdb entry never declares them
      ifoddpage
      relsize
      algorithms
      bbold
      bbold-type1
      cleveref
      eepic
      libertine
      paralist
      stmaryrd
      wrapfig
      acmart
      # acmart loads these; its tlpdb entry never declares them
      comment
      draftwatermark
      environ
      hyperxmp
      ifmtarg
      inconsolata # zi4
      ncctools # manyfoot
      newtx # newtxmath
      preprint # balance
      totpages
      xstring
    ]))
    optimized.lsp-plugins
    optimized.easyeffects
    optimized.quickshell
    snappy-switcher
    dd-cli
    linux-devmgmt
    vicinae
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
    neovide
    alacritty
    ghostty
    tmux
    discord
    obsidian
    slack
    thunderbird
    obs-studio
    zathura
    libreoffice
    vscode
    zed-editor
    lmstudio
    chatgpt
    comfyui
    (helium.override {
      commandLineArgs = [
        # The AirDrop context-menu entry ([[airdrop]]).
        "--load-extension=${../desktopctl/browser}"
        "--disk-cache-size=536870912"
      ];
    })
    imv
    nautilus
    glib # gsettings and gdk-pixbuf: Nautilus thumbnails fail without them
    gdk-pixbuf
    gedit
    haruna
    ffmpeg
    zoom-us
    tor-browser
    fstl
    anki
    gimp
    krita
    prismlauncher
    qbittorrent
    telegram-desktop
    pavucontrol
    ableton-wine
    bambu-studio
    pandoc
    hyprpolkitagent
    hyprsunset
    awww
    lutgen
    brightnessctl
    ddcutil
    grim
    slurp
    wl-clipboard
    playerctl
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
    antigravity-cli
    t3code
  ] ++ (with kdePackages; [
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
  ]);
}
