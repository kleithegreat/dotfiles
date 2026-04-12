{ pkgs, ... }:

{
  # The desktop kernel currently ships ntsync as a module. Load it at boot so
  # Wine 11 can use kernel-backed NT synchronization primitives.
  boot.kernelModules = [ "ntsync" ];

  # WineASIO talks JACK, so expose PipeWire's JACK shim and pw-jack.
  services.pipewire.jack.enable = true;

  environment.systemPackages = with pkgs; [
    # Live 12 Lite is 64-bit only, so stay on Wine 11's WoW64 build instead of
    # enabling NixOS-wide 32-bit graphics support just for this host workflow.
    wineWow64Packages.stableFull
    wineasio
    winetricks
  ];
}
