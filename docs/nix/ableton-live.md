# Ableton Live 12 Lite on the Desktop Host

This repo's desktop host configuration provides the system pieces needed to run
Ableton Live 12 Lite through Wine with PipeWire audio:

- `hosts/desktop/wine-ableton.nix` loads the `ntsync` kernel module at boot.
- `hosts/desktop/wine-ableton.nix` enables `services.pipewire.jack.enable` so
  PipeWire exposes the JACK compatibility layer and `pw-jack`.
- `hosts/desktop/wine-ableton.nix` installs
  `wineWow64Packages.stableFull`, `wineasio`, and `winetricks`.
- `home/default.nix` installs an `ableton-live-12-lite` wrapper command on the
  desktop host and overrides the Wine-generated desktop entry so Vicinae and
  other menu launchers use the working Wine environment instead of plain `wine`.
- `home/default.nix` also installs `ableton-live-12-lite-x11` and
  `ableton-live-12-lite-x11-desktop` plus matching desktop entries for testing
  Xwayland and Xwayland-with-Wine-virtual-desktop launch paths.

This setup intentionally does not use `buildFHSEnv` or `steam-run`. The current
desktop nixpkgs input already provides Wine 11 WoW64 packages, and Live 12 Lite
is a 64-bit Windows application, so an extra FHS wrapper and NixOS-wide 32-bit
graphics stack are unnecessary unless a future installer proves otherwise.

The working setup is split between declarative host/user config and mutable
prefix state:

- Declarative in the repo: kernel/audio packages, the `ableton-live-12-lite`
  launcher wrappers, the Wine desktop-entry override used by Vicinae, and the
  Hyprland float rules for both direct Ableton windows and the Wine virtual
  desktop host window.
- Mutable in the prefix: the Wine prefix itself, the Ableton install, DXVK DLL
  copies, DLL overrides, and small Ableton/Wine preference files.

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
wine "$HOME/.cache/ableton-live-12-installer/Ableton Live 12 Lite Installer.exe"
```

## WineASIO Registration

WineASIO is installed system-wide, but each Wine prefix still needs a one-time
registration step:

```bash
cp /run/current-system/sw/lib/wine/x86_64-windows/wineasio64.dll \
  "$WINEPREFIX/drive_c/windows/system32/"
wine regsvr32 /run/current-system/sw/lib/wine/x86_64-unix/wineasio64.dll.so
```

If you recreate the prefix, rerun those commands.

## Prefix Runtime Tweaks

The current working prefix also needs a few imperative post-install tweaks.

### DXVK

Copy DXVK's D3D/DXGI DLLs into the prefix and set native overrides for them.
This avoids the less stable `wined3d` OpenGL path that caused blank or stale UI
regions and frequent crashes on the desktop host.

### Native VC++ Runtime Overrides

The Ableton background indexer hit unimplemented Wine `msvcp140.dll` symbols
until the prefix was forced to use the Microsoft VC++ runtime DLLs already
installed by the Ableton setup chain. Keep those overrides in the prefix if you
recreate it.

### DPI Awareness Override

Ableton's own log reported `Effective process DPI awareness: 0` under Wine even
though the app expects per-monitor DPI awareness. The prefix now carries an
Image File Execution Options override for `Ableton Live 12 Lite.exe` with
`dpiAwareness=2`, which at least moves the process out of the fully DPI-unaware
mode. This did not fully fix the click-target mismatch, but it is part of the
current tested prefix state.

### Options.txt

Create:

```text
~/.local/share/wineprefixes/ableton-live-12-lite/drive_c/users/kevin/AppData/Roaming/Ableton/Live 12.3.6/Preferences/Options.txt
```

with:

```text
-DisableAutoBugReporting
```

That suppresses repeated modal crash-report dialogs while the prefix is still
rough around the edges.

## Launch Command

The tested launcher commands are:

```bash
ableton-live-12-lite
ableton-live-12-lite-x11
ableton-live-12-lite-x11-desktop
```

They all set the same `WINEPREFIX` and launch through `pw-jack`, but differ in
their display path:

- `ableton-live-12-lite`: Wine Wayland path via
  `WINEDLLOVERRIDES=winepulse.drv=d;winex11.drv=d`
- `ableton-live-12-lite-x11`: Xwayland path via
  `WINEDLLOVERRIDES=winepulse.drv=d;winewayland.drv=d`
- `ableton-live-12-lite-x11-desktop`: the same Xwayland path, but wrapped in a
  fixed-size Wine virtual desktop using `wine explorer /desktop=Ableton,1600x900`

Use that wrapper for terminal launches. Vicinae and other app launchers should
use the same command through the Home Manager override at
`~/.local/share/applications/wine/Programs/Ableton Live 12 Lite.desktop` and the
additional desktop entries under `~/.local/share/applications/`.

## External Research

The most useful current references found during debugging were:

- `BEEFY-JOE/AbletonLiveOnLinux`:
  <https://github.com/BEEFY-JOE/AbletonLiveOnLinux>
  This is the closest public symptom match. It documents Live 12 on Wayland and
  explicitly notes that non-fullscreen windowed mode has inaccurate mouse
  coordinates, drawing/scaling issues, and effectively needs fullscreen.
- `korewaChino/live-on-linux`:
  <https://github.com/korewaChino/live-on-linux>
  Practical current guide recommending a fresh prefix, `vcrun2015` /
  `vcrun2017`, wrapper-based launching, and resetting Max preferences.
- `nine7nine/Wine-NSPA issue #4`:
  <https://github.com/nine7nine/Wine-NSPA/issues/4>
  Strong technical notes from a pro-audio Wine maintainer. Documents Live 11/12
  as usable on a custom Wine branch, recommends DXVK for some crashes, and calls
  out `-DontCombineAPCs` and Tracker indexing issues.
- `stotes/AbletonAuthorizeCloudWine`:
  <https://gist.github.com/stotes/78ad62db297b9efcb4d36646ef8bd481>
  Useful manual workaround when Ableton's browser-based authorization handoff is
  broken and the app needs an `ableton://...` URI passed in directly.
- Microsoft DPI-awareness docs:
  <https://learn.microsoft.com/en-us/windows/win32/hidpi/setting-the-default-dpi-awareness-for-a-process>
  and
  <https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setprocessdpiawarenesscontext>
  These matter because they explicitly recommend manifest-level DPI awareness,
  not late API calls, and warn that the default process mode is DPI-unaware if
  nothing sets it early.

Research-backed takeaways:

- The repo's overall approach is aligned with what current Linux/NixOS users are
  actually doing: fresh `win64` prefix, current Wine, PipeWire JACK via
  `pw-jack`, `WineASIO`, wrapper scripts, and no dependence on the plain
  Wine-generated desktop entry.
- The strongest remaining suspect is Wine's DPI/client-area handling for
  Ableton, not NixOS package naming, PipeWire wiring, or Hyprland rules.
- Windowed mode itself appears to be an upstream problem area for recent
  Ableton-on-Wine setups. Fullscreen and virtual-desktop workarounds show up in
  multiple current references, with the BEEFY-JOE guide matching this setup's
  symptoms especially closely.

Then in Ableton's audio settings choose:

- Driver Type: `ASIO`
- Audio Device: `WineASIO`

The default PipeWire/WirePlumber configuration is left alone because this host
only needs reliable playback for production work, not special low-latency live
performance tuning.

## Current Caveats

- The plain Wine-generated launcher is known-bad and should not be used.
- The Wine Wayland path launches, but consistently clips some amount of the
  bottom UI and shifts click targeting enough to make editor split bars and note
  edge dragging unreliable.
- External reports corroborate that recent Ableton-on-Wine setups can have
  inaccurate mouse coordinates specifically in non-fullscreen windowed mode.
- The Xwayland path avoids the bottom clipping and restores normal `Delete` key
  behavior, but click targeting is still misaligned in tested sessions.
- The Xwayland path has also shown cases where the Ableton authorization notice
  popup appears but is difficult or impossible to interact with.
- A tested X11-driver experiment with `Managed=N` and `Decorated=N` reduced
  flicker and made the authorization popup easier to click, but made cursor
  targeting substantially worse and was reverted from the live prefix.
- The fixed-size Wine virtual desktop (`Ableton - Wine Desktop`, class
  `explorer.exe`) keeps the whole app inside one Xwayland host window, but did
  not eliminate the click-target misalignment.
- The remaining click drift pattern is proportional to the vertical mouse
  position, which strongly suggests a client-height or DPI-awareness mismatch
  rather than a random compositor focus bug.
- Keep Ableton floating in Hyprland; the repo has explicit rules for class
  `ableton live 12 lite.exe` and the virtual desktop host window
  `explorer.exe` titled `Ableton - Wine Desktop`.

## Useful Checks

After the rebuild and reboot, these commands should succeed:

```bash
ls -l /dev/ntsync
which pw-jack
systemctl --user --no-pager --type=service --state=running | rg 'pipewire|wireplumber'
```

If Ableton starts but `WineASIO` is missing from the audio device list, rerun
the registration commands in the same prefix and launch the app again with
`ableton-live-12-lite`.
