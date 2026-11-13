{ config, pkgs, lib, ... }:

{
  systemd.user.services.desktopctl = {
    Unit = {
      Description = "desktopctl desktop daemon";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };

    Service = {
      ExecStart = "${lib.getExe pkgs.optimized.desktopctl} daemon";
      Restart = "on-failure";
      RestartSec = 1;
    };

    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ── AirDrop's context-menu entries ([[airdrop]]) ──────────────────────
  # Helium loads the extension in desktopctl/browser (home/packages.nix).
  home.file.".config/net.imput.helium/NativeMessagingHosts/desktopctl.airdrop.json".text =
    builtins.toJSON {
      name = "desktopctl.airdrop";
      description = "AirDrop from the context menu";
      path = pkgs.writeShellScript "airdrop-native-host" ''
        exec ${lib.getExe pkgs.optimized.desktopctl} airdrop native-host "$@"
      '';
      type = "stdio";
      allowed_origins = [ "chrome-extension://piklfcmpjcamnibeokbpnhmlanlpdmon/" ];
    };

  home.packages = [ pkgs.nautilus-python ];
  # Nautilus reads one extension directory; the profile's holds its own and nautilus-python's.
  home.sessionVariables.NAUTILUS_4_EXTENSION_DIR = "${config.home.profileDirectory}/lib/nautilus/extensions-4";
  xdg.dataFile."nautilus-python/extensions/airdrop.py".text = /* python */ ''
    import subprocess

    from gi.repository import GObject, Nautilus


    class AirDrop(GObject.GObject, Nautilus.MenuProvider):
        def get_file_items(self, files):
            paths = [file.get_location().get_path() for file in files]
            if not paths or None in paths:
                return []
            item = Nautilus.MenuItem(name="AirDrop::share", label="AirDrop")
            item.connect("activate", lambda _: subprocess.Popen(
                ["${lib.getExe pkgs.optimized.desktopctl}", "airdrop", "share", "--", *paths]))
            return [item]
  '';

  home.activation.applyTheme = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH="${lib.makeBinPath [ pkgs.optimized.desktopctl ]}:$PATH"
    mkdir --parents "$HOME/.config/hypr"
    # Empty is the "no overrides" state the Lua appliers expect.
    touch "$HOME/.config/hypr/input-runtime.lua"
    touch "$HOME/.config/hypr/displays-runtime.lua"
    desktopctl theme sync
  '';
}
