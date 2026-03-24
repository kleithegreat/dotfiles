{ config, pkgs, ... }:

let
  neuwaita = pkgs.stdenvNoCC.mkDerivation {
    pname = "neuwaita";
    version = "unstable";
    src = pkgs.fetchFromGitHub {
      owner = "RusticBard";
      repo = "Neuwaita";
      rev = "main";
      sha256 = "sha256-A4yfcB+L1IwHGKhg32gq/E9qMoBF84zsnfl8fvWhYag=";
    };
    installPhase = ''
      mkdir -p $out/share/icons/Neuwaita
      cp -r index.theme scalable Extras $out/share/icons/Neuwaita/
    '';
  };
in
{
  gtk = {
    enable = true;
    theme = {
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Neuwaita";
      package = neuwaita;
    };
    cursorTheme = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
    };
    font = {
      name = "Overpass";
      size = 11;
    };
    gtk3.extraConfig.gtk-application-prefer-dark-theme = true;
    gtk4.theme = config.gtk.theme;
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

}