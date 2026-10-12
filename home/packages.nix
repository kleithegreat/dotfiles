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
    algorithm2e
    # algorithm2e loads these; its tlpdb entry never declares them
    ifoddpage
    relsize
    algorithms
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

  basePackages = with pkgs; [
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
    discord
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
