{ pkgs, ... }:

{
  # The only channel that reaches every Qt app (docs/theming.md).
  qt = {
    enable = true;
    style = "kvantum";
  };

  # By hand: `qt.platformTheme`'s qt5ct value writes a key the Qt6 plugin does not register.
  environment.sessionVariables.QT_QPA_PLATFORMTHEME = "qt6ct";

  environment.systemPackages = [ pkgs.qt6Packages.qt6ct ];
}
