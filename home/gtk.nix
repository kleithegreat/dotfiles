{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (lib.attrsets) mergeAttrsList;
  inherit (lib.lists) map;
  cssImport = path: /* css */ ''
    @import url("file://${path}");
  '';
in
{
  home.packages = [
    pkgs.adwaita-icon-theme
    pkgs.colloid-icon-theme
    pkgs.neuwaita
    pkgs.papirus-icon-theme
  ];

  # Both variants load the scheme.css desktopctl's gtk target writes, which picks
  # light.css or dark.css; libhandy picks the variant by the browser's polarity.
  xdg.dataFile =
    [
      "gtk-3.0"
      "gtk-4.0"
    ]
    |> map (
      toolkit:
      let
        file = name: "themes/desktopctl/${toolkit}/${name}";
        scheme = cssImport "${config.xdg.dataHome}/${file "scheme.css"}";
        base = theme: cssImport "${pkgs.adw-gtk3}/share/themes/${theme}/${toolkit}/gtk.css";
      in
      {
        ${file "gtk.css"}.text = scheme;
        ${file "gtk-dark.css"}.text = scheme;
        ${file "light.css"}.text = base "adw-gtk3";
        ${file "dark.css"}.text = base "adw-gtk3-dark";
      }
    )
    |> mergeAttrsList;

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
