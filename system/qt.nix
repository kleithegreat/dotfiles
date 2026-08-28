{ pkgs, ... }:

{
  # `style` sets QT_STYLE_OVERRIDE and installs both Kvantum plugins. It is the
  # only channel that reaches every Qt app: qt6ct's own style setting loses to
  # KStyleManager inside KDE apps, and Qt5 has no platform theme here at all.
  qt = {
    enable = true;
    style = "kvantum";
  };

  # Set by hand rather than through `qt.platformTheme`, whose `qt5ct` value
  # writes a key the Qt6 plugin does not register. qt6ct supplies palette,
  # fonts, icon theme and standard dialogs; Kvantum supplies both to Qt5.
  environment.sessionVariables.QT_QPA_PLATFORMTHEME = "qt6ct";

  # KDE colour infrastructure ignores QPalette outside Plasma and reads this
  # path instead; the `qt` theme target generates the file it points at.
  environment.sessionVariables.KDE_COLOR_SCHEME_PATH =
    "$HOME/.local/share/color-schemes/current.colors";

  environment.systemPackages = [ pkgs.qt6Packages.qt6ct ];
}
