{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib.attrsets) concatMapAttrs;
in
{
  home.packages = [
    pkgs.adwaita-icon-theme
    pkgs.colloid-icon-theme
    pkgs.neuwaita
    pkgs.papirus-icon-theme
  ];

  # adw-gtk3 recoloured by the colors.css desktopctl's gtk target writes beside each theme.
  xdg.dataFile =
    {
      desktopctl = "adw-gtk3";
      desktopctl-dark = "adw-gtk3-dark";
    }
    |> concatMapAttrs (
      name: base: {
        "themes/${name}/gtk-3.0/gtk.css".text = /* css */ ''
          @import url("file://${pkgs.adw-gtk3}/share/themes/${base}/gtk-3.0/gtk.css");
          @import url("file://${config.xdg.dataHome}/themes/${name}/gtk-3.0/colors.css");
        '';
        "themes/${name}/gtk-4.0/gtk.css".text = /* css */ ''
          @import url("file://${pkgs.adw-gtk3}/share/themes/${base}/gtk-4.0/gtk.css");
        '';
      }
    );

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      clock-format = "12h";
    };
    "org/gnome/nautilus/preferences" = {
      show-image-thumbnails = "always";
      thumbnail-limit = lib.hm.gvariant.mkUint64 100;
    };
  };
}
