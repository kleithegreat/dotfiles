{ config, pkgs, ... }:

let
  neuwaita = pkgs.stdenvNoCC.mkDerivation {
    pname = "neuwaita";
    version = "unstable";
    src = pkgs.fetchFromGitHub {
      owner = "RusticBard";
      repo = "Neuwaita";
      rev = "main";
      sha256 = "sha256-ixMo4n2hrXe3iWm/HjZsAK2892UA42NB7tBJ905L740=";
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
    gtk4.extraConfig.gtk-application-prefer-dark-theme = true;
  };

  home.pointerCursor = {
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
    x11.enable = true;
  };

  home.packages = with pkgs; [
    overpass
    adw-gtk3
  ];
}