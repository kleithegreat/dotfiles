{ where-is-my-sddm-theme }:

let
  backgroundDir = "/var/lib/desktopctl/where-is-my-sddm-theme";
  backgroundPath = "${backgroundDir}/background";
in
(where-is-my-sddm-theme.override {
  themeConfig.General = {
    background = backgroundPath;
    backgroundMode = "fill";
    blurRadius = 32;
    basicTextColor = "#ebdbb2";
    passwordCharacter = "*";
    passwordFontSize = 36;
    passwordInputBackground = "#3c3836";
    passwordInputRadius = 8;
    passwordInputWidth = 0.25;
    passwordCursorColor = "#ebdbb2";
    passwordMask = true;
    passwordInputCursorVisible = true;
    showUsersByDefault = true;
    showUserRealNameByDefault = true;
    usersFontSize = 24;
    showSessionsByDefault = false;
    sessionsFontSize = 16;
  };
}).overrideAttrs (old: {
  passthru = (old.passthru or { }) // { inherit backgroundDir backgroundPath; };
})
