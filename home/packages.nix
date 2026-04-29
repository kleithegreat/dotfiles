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
  ];

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
    neovim
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
    vscode
    lmstudio
    helium
    imv
    nautilus
    gedit
    harunaPkg
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
    gnome-secrets
    orca-slicer
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
    # Hyprland sessions need the ksystemstats user D-Bus service in the profile
    # or plasma-systemmonitor shows empty widgets with missing sensors.
    ksystemstats
    plasma-systemmonitor
    kate
    gwenview
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

  services.vicinae = {
    enable = true;
    package = vicinaePkg;
  };
}
