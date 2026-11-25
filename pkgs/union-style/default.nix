{
  runCommand,
  writeText,
  kdePackages,
}:

let
  breeze = "${kdePackages.union}/share/union/styles/breeze/contents";
  # First definition of a variable wins, so the tokens override Breeze's by preceding them.
  style = writeText "style.css" /* css */ ''
    @import "tokens.css";
    @import "${breeze}/css/style.css";
    @import "controls.css";
  '';
in
runCommand "union-style" { } /* bash */ ''
  style=$out/share/union/styles/desktopctl
  mkdir --parents $style/contents/css
  cp ${./metadata.json} $style/metadata.json
  cp ${style} $style/contents/css/style.css
  cp ${./controls.css} $style/contents/css/controls.css
  cp --recursive ${breeze}/images $style/contents/images
''
