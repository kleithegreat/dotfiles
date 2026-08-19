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
    ./desktopctl.nix
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

  programs.chromium = {
    enable = true;
    extensions = browserExtensions;
  };

  home.file = heliumExtensionFiles;

  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}
