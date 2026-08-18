{ config, pkgs, lib, ... }:

let
  browserExtensions = [
    "ddkjiahejlhfcafbddmgiahcphecmpfh"
    "nngceckbapebfimnlniiiahkandclblb"
    "nkbihfbeogaeaoehlefnkodbefgpgknn"
    "bfnaelmomeimhlpmgjnjophhpkkoljpa"
  ];

  heliumExtensionFiles =
    browserExtensions
    |> map (id: {
      name = ".config/net.imput.helium/External Extensions/${id}.json";
      value.text = builtins.toJSON {
        external_update_url = "https://clients2.google.com/service/update2/crx";
      };
    })
    |> lib.listToAttrs;
in
{
  imports = [
    ./shell.nix
    ./gtk.nix
    ./packages.nix
    ./xdg.nix
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
    PATH="${lib.makeBinPath [ pkgs.optimized.desktopctl ]}:$PATH"
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
