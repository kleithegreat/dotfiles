{ pkgs, ... }:

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
      substituteInPlace $out/share/icons/Neuwaita/index.theme \
        --replace-fail 'Inherits=Adwaita, hicolor, breeze' $'Inherits=breeze,Adwaita,hicolor\nFollowsColorScheme=true'
    '';
  };
in
{
  # Theme packages stay declarative; the theme switcher owns the active settings.
  home.packages = [
    pkgs.adw-gtk3
    pkgs.adwaita-icon-theme
    pkgs.colloid-icon-theme
    neuwaita
  ];

  # ── dconf / GNOME settings ───────────────────────────────────
  dconf.settings = {
    "org/gnome/desktop/interface" = {
      clock-format = "12h";
    };
  };
}
