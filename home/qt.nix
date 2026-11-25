{ pkgs, ... }:

{
  # Linked file by file: desktopctl's qt target writes tokens.css beside the stylesheet.
  xdg.dataFile."union/styles/desktopctl" = {
    source = "${pkgs.union-style}/share/union/styles/desktopctl";
    recursive = true;
  };
}
