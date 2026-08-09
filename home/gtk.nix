{ lib, pkgs, ... }:

{
  # Theme packages stay declarative; the theme switcher owns the active settings.
  home.packages = [
    pkgs.adw-gtk3
    pkgs.adwaita-icon-theme
    pkgs.colloid-icon-theme
    pkgs.neuwaita
  ];

  # ── dconf / GNOME settings ───────────────────────────────────
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
