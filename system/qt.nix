{ pkgs, ... }:

{
  # KDE's platform theme makes kdeglobals the one input every Qt app reads (docs/theming.md).
  qt = {
    enable = true;
    platformTheme = "kde";
  };

  environment = {
    systemPackages = [ pkgs.kdePackages.union ];
    pathsToLink = [ "/share/union" ];
    variables = {
      # Union picks its Plasma platform plugin only on a KDE session.
      UNION_FORCE_PLATFORM = "plasma";
      # Its cache is validated by mtime, and every store mtime is equal.
      UNION_DISABLE_STYLE_CACHE = "1";
    };
  };
}
