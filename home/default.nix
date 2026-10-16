{ pkgs, lib, ... }:

let
  browserExtensions = [
    "ddkjiahejlhfcafbddmgiahcphecmpfh"
    "nngceckbapebfimnlniiiahkandclblb"
    "nkbihfbeogaeaoehlefnkodbefgpgknn"
    "bfnaelmomeimhlpmgjnjophhpkkoljpa"
    "fcoeoabgfenejglbffodgkkbkcdhcgfn"
  ];

  heliumExtensionFiles =
    browserExtensions
    |> map (id: {
      name = ".config/net.imput.helium/External Extensions/${id}.json";
      value.text = builtins.toJSON {
        external_update_url = "https://clients2.google.com/service/update2/crx";
      };
    })
    |> lib.listToAttrs;

  # Claude Code registers this host only for browsers it knows, which excludes Helium.
  claudeChromeNativeHost = pkgs.writeShellScript "claude-chrome-native-host" ''
    exec ${lib.getExe pkgs.claude-code} --chrome-native-host
  '';
in
{
  imports = [
    ./desktopctl.nix
    ./shell.nix
    ./gtk.nix
    ./packages.nix
    ./xdg.nix
  ];

  xdg = {
    enable = true;
    userDirs = {
      enable = true;
      setSessionVariables = true;
      createDirectories = true;
    };
  };

  programs.git.settings.credential.helper =
    lib.getExe' pkgs.gitFull "git-credential-libsecret";

  programs.chromium = {
    enable = true;
    extensions = browserExtensions;
  };

  home.file = heliumExtensionFiles // {
    ".config/net.imput.helium/NativeMessagingHosts/com.anthropic.claude_code_browser_extension.json".text =
      builtins.toJSON {
        name = "com.anthropic.claude_code_browser_extension";
        description = "Claude Code Browser Extension Native Host";
        path = claudeChromeNativeHost;
        type = "stdio";
        allowed_origins = [ "chrome-extension://fcoeoabgfenejglbffodgkkbkcdhcgfn/" ];
      };
  };

  programs.home-manager.enable = true;
  home.stateVersion = "25.05";
}
