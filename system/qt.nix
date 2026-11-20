{ ... }:

{
  # KDE's platform theme makes kdeglobals the one input every Qt app reads (docs/theming.md).
  qt = {
    enable = true;
    platformTheme = "kde";
    style = "breeze";
  };
}
