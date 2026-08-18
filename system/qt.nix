{ pkgs, inputs, ... }:

let
  system = pkgs.stdenv.hostPlatform.system;
  hyprqt6engine = pkgs.optimize.cc (inputs.hyprqt6engine.packages.${system}.default.overrideAttrs (old: {
    buildInputs = (old.buildInputs or []) ++ [
      pkgs.kdePackages.kcolorscheme
      pkgs.kdePackages.kconfig
      pkgs.kdePackages.kiconthemes
    ];
  }));
in
{
  qt.enable = true;
  environment.sessionVariables.QT_QPA_PLATFORMTHEME = "hyprqt6engine";
  # hyprqt6engine installs its platform theme outside the standard Qt plugin
  # roots, so keep its qt-6 prefix visible while qt.enable wires the normal
  # profile plugin and QML import paths.
  environment.sessionVariables.QT_PLUGIN_PATH = [
    "${hyprqt6engine}/lib/qt-6"
  ];

  environment.systemPackages = [
    pkgs.libsForQt5.qt5ct
    pkgs.qt6Packages.qt6ct
    pkgs.kdePackages.qtstyleplugin-kvantum
    pkgs.libsForQt5.qtstyleplugin-kvantum
    hyprqt6engine
  ];
}
