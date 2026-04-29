{ config, pkgs, lib, dotfilesPath, host, vicinae, snappy-switcher, inputs, enableNativeOptimizations, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  stablePkgs = import inputs.nixpkgs-stable { inherit system; };
  nativeOptimizations = import ../system/native-optimizations.nix {
    inherit lib host enableNativeOptimizations;
  };
  optimizedPackages = import ../overlays/native-optimized.nix {
    inherit lib inputs host enableNativeOptimizations;
  };
  optimizedPkgs = pkgs.appendOverlays [ optimizedPackages.overlay ];
  inherit (optimizedPkgs)
    desktopctl
    fd
    lapce
    p7zip
    quickshell
    ripgrep
    ;
  lspPlugins = optimizedPkgs.lsp-plugins;
  opencodePkg = pkgs.opencode;
  harunaPkg = stablePkgs.haruna;
  snappySwitcherPkg = nativeOptimizations.optimizeNativePackage (snappy-switcher.packages.${system}.default.overrideAttrs (old: {
    patches = (old.patches or []) ++ [
      ../patches/snappy-switcher/workspace-scope-filter.patch
    ];
  }));
  vicinaePkg = nativeOptimizations.optimizeNativePackage vicinae.packages.${system}.default;
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
in
{
  imports = [
    ./shell.nix
    ./gtk.nix
    ./fastfetch.nix
    vicinae.homeManagerModules.default
    (import ./packages.nix {
      inherit pkgs desktopctl fd lapce p7zip quickshell ripgrep opencodePkg harunaPkg vicinaePkg texlive;
      inherit lspPlugins;
      snappySwitcherPkg = snappySwitcherPkg;
    })
    (import ./xdg.nix {
      inherit config lib pkgs dotfilesPath host;
      snappySwitcherPkg = snappySwitcherPkg;
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
    touch "$HOME/.config/hypr/input-runtime.conf"
    touch "$HOME/.config/hypr/animations-override.conf"
    touch "$HOME/.config/hypr/keybinds-override.conf"
    desktopctl theme sync
  '';

  programs.chromium = {
    enable = true;
    extensions = [
      "ddkjiahejlhfcafbddmgiahcphecmpfh"
      "nngceckbapebfimnlniiiahkandclblb"
      "nkbihfbeogaeaoehlefnkodbefgpgknn"
      "bfnaelmomeimhlpmgjnjophhpkkoljpa"
    ];
  };

  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}
