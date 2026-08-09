{ config, pkgs, lib, dotfilesPath, host, inputs, enableNativeOptimizations, ... }:

let
  optimizedPackages = import ../overlays/native-optimized.nix {
    inherit lib inputs host enableNativeOptimizations;
  };
  optimizedPkgs = pkgs.appendOverlays [ optimizedPackages.overlay ];
  inherit (optimizedPkgs)
    desktopctl
    fd
    p7zip
    quickshell
    ripgrep
    ;
  lspPlugins = optimizedPkgs.lsp-plugins;
  opencodePkg = pkgs.opencode;
  # Haruna needs to stay on the session Qt/KDE stack so the global
  # hyprqt6engine platform theme plugin is ABI-compatible.
  harunaPkg = pkgs.haruna;
  snappySwitcherPkg = pkgs.snappy-switcher;
  bambuStudioPkg = pkgs.bambu-studio;
  vicinaePkg = pkgs.vicinae;
  texlive = optimizedPkgs.texlive.withPackages (ps: with ps; [
    scheme-small
    latexmk
    tikz-cd
    titlesec
    tocloft
    enumitem
    mdframed
    needspace
    zref
  ]);

  browserExtensions = [
    "ddkjiahejlhfcafbddmgiahcphecmpfh"
    "nngceckbapebfimnlniiiahkandclblb"
    "nkbihfbeogaeaoehlefnkodbefgpgknn"
    "bfnaelmomeimhlpmgjnjophhpkkoljpa"
  ];

  heliumExtensionFiles = lib.listToAttrs (map (id: {
    name = ".config/net.imput.helium/External Extensions/${id}.json";
    value.text = builtins.toJSON {
      external_update_url = "https://clients2.google.com/service/update2/crx";
    };
  }) browserExtensions);
in
{
  imports = [
    ./shell.nix
    ./gtk.nix
    (import ./packages.nix {
      inherit pkgs desktopctl fd p7zip quickshell ripgrep opencodePkg harunaPkg vicinaePkg texlive;
      inherit lspPlugins;
      snappySwitcherPkg = snappySwitcherPkg;
    })
    (import ./xdg.nix {
      inherit lib dotfilesPath host;
      snappySwitcherPkg = snappySwitcherPkg;
      bambuStudioPkg = bambuStudioPkg;
    })
  ];

  home.username = "kevin";
  home.homeDirectory = "/home/kevin";

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

  programs.git.settings.credential.helper =
    "${pkgs.gitFull}/bin/git-credential-libsecret";

  home.activation.applyTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH="${lib.makeBinPath [ desktopctl ]}:$PATH"
    mkdir -p "$HOME/.config/hypr"
    # Seed the desktopctl-managed data tables. An empty file is the "no
    # overrides" state: the Lua appliers guard their require, and `desktopctl
    # hypr {animations,keybinds} clear` truncates back to empty.
    touch "$HOME/.config/hypr/input-runtime.lua"
    touch "$HOME/.config/hypr/animations-override-data.lua"
    touch "$HOME/.config/hypr/keybinds-override-data.lua"
    desktopctl theme sync
  '';

  programs.chromium = {
    enable = true;
    extensions = browserExtensions;
  };

  home.file = heliumExtensionFiles;

  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}
