# Ableton Live 12 Lite on the Desktop Host

This repo's desktop host configuration provides the system pieces needed to run
Ableton Live 12 Lite through Wine with PipeWire audio:

- `hosts/desktop/wine-ableton.nix` loads the `ntsync` kernel module at boot.
- `hosts/desktop/wine-ableton.nix` enables `services.pipewire.jack.enable` so
  PipeWire exposes the JACK compatibility layer and `pw-jack`.
- `hosts/desktop/wine-ableton.nix` installs
  `wineWow64Packages.stableFull`, `wineasio`, and `winetricks`.

This setup intentionally does not use `buildFHSEnv` or `steam-run`. The current
desktop nixpkgs input already provides Wine 11 WoW64 packages, and Live 12 Lite
is a 64-bit Windows application, so an extra FHS wrapper and NixOS-wide 32-bit
graphics stack are unnecessary unless a future installer proves otherwise.

## Rebuild

```bash
sudo nixos-rebuild switch --flake ~/repos/dotfiles#desktop
sudo reboot
```

The reboot ensures the boot-time `ntsync` module load is in effect.

## Prefix Location

Keep the prefix in the home directory, not in the Nix store. The suggested path
is:

```text
~/.local/share/wineprefixes/ableton-live-12-lite
```

Use a fresh prefix for this workflow. Current nixpkgs Wine 11 packages use the
new `wineWow64Packages` layout, so old prefixes built around deprecated
`wineWowPackages` are not assumed to be compatible.

## Prefix Creation

```bash
export WINEPREFIX="$HOME/.local/share/wineprefixes/ableton-live-12-lite"
export WINEARCH=win64
wineboot -u
```

## Installer Extraction

Extract the Ableton zip into a normal writable directory and run the installer
from that extracted directory so the adjacent `Installer-*.bin` files stay next
to the `.exe`.

Example:

```bash
mkdir -p "$HOME/.cache/ableton-live-12-installer"
unzip "$HOME/Downloads/<ableton-live-zip>.zip" -d "$HOME/.cache/ableton-live-12-installer"
wine64 "$HOME/.cache/ableton-live-12-installer/Ableton Live 12 Lite Installer.exe"
```

## WineASIO Registration

WineASIO is installed system-wide, but each Wine prefix still needs a one-time
registration step:

```bash
cp /run/current-system/sw/lib/wine/x86_64-windows/wineasio64.dll \
  "$WINEPREFIX/drive_c/windows/system32/"
wine64 regsvr32 /run/current-system/sw/lib/wine/x86_64-unix/wineasio64.dll.so
```

If you recreate the prefix, rerun those commands.

## First Launch

Launch Ableton through `pw-jack` so WineASIO sees PipeWire's JACK layer:

```bash
pw-jack wine64 "$WINEPREFIX/drive_c/ProgramData/Ableton/Live 12 Lite/Program/Ableton Live 12 Lite.exe"
```

Then in Ableton's audio settings choose:

- Driver Type: `ASIO`
- Audio Device: `WineASIO`

The default PipeWire/WirePlumber configuration is left alone because this host
only needs reliable playback for production work, not special low-latency live
performance tuning.

## Useful Checks

After the rebuild and reboot, these commands should succeed:

```bash
ls -l /dev/ntsync
which pw-jack
systemctl --user --no-pager --type=service --state=running | rg 'pipewire|wireplumber'
```

If Ableton starts but `WineASIO` is missing from the audio device list, rerun
the registration commands in the same prefix and launch the app again with
`pw-jack`.
