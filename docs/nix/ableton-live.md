# Ableton Live 12 Lite on the Desktop Host

This document is kept as a historical investigation log and setup record. The
active desktop host configuration and local user wiring for Ableton/Wine were
removed from the machine-facing config, but the notes are retained so future
investigation can resume from the current evidence instead of starting over.

At the time of the investigation, the repo's desktop host configuration provided
the system pieces needed to run Ableton Live 12 Lite through Wine with PipeWire
audio:

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

- Declarative at the time of the investigation: kernel/audio packages, the
  `ableton-live-12-lite` launcher wrappers, the Wine desktop-entry override
  used by Vicinae, and the Hyprland float rules for both direct Ableton windows
  and the Wine virtual desktop host window.
- Mutable in the prefix: the Wine prefix itself, the Ableton install, DXVK DLL
  copies, DLL overrides, and small Ableton/Wine preference files.
- Local-only ad hoc test assets used during investigation are not declarative:
  copied EXEs, temporary wrappers under `~/.local/bin/`, the extracted
  `~/.cache/wine-nspa/` trees, and in-place source patches applied while trying
  to build Wine-NSPA.

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

### Embedded Manifest Experiment

An external sidecar manifest placed next to `Ableton Live 12 Lite.exe` was not
enough, because the EXE already ships an embedded `MANIFEST/1` resource and
Wine 11 appears to prefer it. A copied test EXE with a patched embedded
`PerMonitorV2` manifest did make Ableton's log report `Effective process DPI
awareness: 2`, but the visible UI clipping and hit-testing problems remained
unchanged.

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

## Investigation Log

The key confirmed findings from the hands-on investigation so far are:

- System prerequisites are in place on the desktop host: the rebuilt kernel
  exposes `/dev/ntsync`, nixpkgs already provides Wine 11+, `wineasio`,
  `winetricks`, `steam-run`, and `buildFHSEnv`, and PipeWire itself is healthy.
- The installer archive was `~/Downloads/ableton_live_lite_12.3.6_64.zip` and
  contained `Ableton Live 12 Lite Installer.exe` plus adjacent `.bin` payloads.
- WineASIO registration in the prefix worked and Ableton's own log reached the
  ASIO device path, so audio-driver setup is not the first blocker.
- The initial startup hang on `Initializing MIDI inputs and outputs` was solved
  only after disabling `winepulse.drv` for the prefix launch environment.
  Without that override, the app repeatedly stalled during MIDI enumeration.
- Installing Ableton's optional USB audio driver inside Wine was not required
  for this setup and was removed as a variable by recreating the prefix without
  it. That did not solve the main hit-testing bug.
- The background `Ableton Index.exe` helper crashed in a restart loop until the
  prefix was forced to use native VC++ runtime DLLs and auto bug reporting was
  suppressed with `Options.txt`.
- DXVK was worth keeping for general stability. It reduced the earlier blank,
  stale, or black UI behavior compared with the `wined3d` path, but it did not
  solve the bottom clipping or input-coordinate mismatch.
- The Wine Wayland path launches most reliably, but it consistently clips the
  bottom of the window. The clipped region is the lower editor area under the
  device chain / piano roll section.
- The Xwayland path removes the bottom clipping and restores expected `Delete`
  key behavior, but the click-target bug remains. The authorization popup is
  often harder to interact with in the plain Xwayland path.
- The Xwayland virtual desktop path (`explorer.exe` titled `Ableton - Wine
  Desktop`) keeps the app inside one host window, but it still does not fix the
  click-target bug.
- The click-target mismatch is proportional to vertical position: the farther
  down the visible cursor is in the window, the farther below the visible UI the
  actual target lands. That pattern held across Wayland, Xwayland, and the Wine
  virtual desktop.
- Hyprland tiling was a secondary aggravator, not the root cause. Floating the
  window is still necessary for usability, but rebuilding with the float rule,
  disabling Hyprbars, disabling Quickshell, and temporarily removing Hyprland
  gaps did not materially change the core hit-testing bug.
- Hyprland fullscreen also did not solve the problem. `F11` inside Ableton was a
  no-op in tested sessions, and compositor fullscreen still left the internal
  client area wrong.
- The strongest renderer-side clue so far came from DXVK logs: swapchain sizes
  repeatedly overshot the visible output height, such as `1908x1096` or
  `1920x1096` on a `1920x1080` output. That aligns closely with the clipped
  bottom edge and the downward-growing input offset.
- Later custom-Wine instrumentation showed that the final `screen_to_client()`
  conversion is internally consistent, but it is subtracting the top-left of a
  top-level editor window that Wine already believes is too tall. In one traced
  run the same window had a stable geometry around `(156,78)-(1764,1174)` while
  earlier X11 `ConfigureNotify` events for that top-level window still reported
  `1600x900` visible sizes. That means the bad click coordinates are likely a
  consequence of stale top-level X11/window geometry state rather than the last
  mouse-message transform itself.
- Deeper child-window instrumentation also showed that the main editor child
  itself was being selected correctly for reproduced clicks; the problem was not
  a random child-window mismatch. The wrong final client coordinates were still
  delivered to Ableton because the top-level/editor origin in Wine was already
  wrong by a consistent amount.
- Later `wine-tkg` producer-side tracing in `win32u/window.c` showed that the
  earliest obvious corruption for the problematic editor child did not start in
  the final `screen_to_client()` call. Instead, repeated `SetWindowPos` /
  `calc_ncsize()` updates for a small child window pushed `new_client.top`
  downward while `new_window` and `new_visible` stayed unchanged, and later
  larger child-window updates still kept `new_client` and `new_visible` out of
  sync. That means the geometry corruption is already present in the Win32
  layout pipeline before the final input transform.
- Ableton's own log initially reported `Effective process DPI awareness: 0`
  while also reporting `ALF DPI awareness: pm-aware v2`. The registry override
  and embedded-manifest experiment were both attempts to reconcile that mismatch.
- Stable Wine 11 and staging Wine 11.5 behaved essentially the same for the GUI
  problem on the tested prefix.

## Custom Wine Experiments

### Wine staging 11.5

`wineWow64Packages.stagingFull` from the current nixpkgs input was available and
testable with the same prefix. It did not materially change the clipping or the
click-target bug compared with the stable Wine 11 package.

### wine-tkg 11.6

A local `wine-tkg` build based on `11.6.r2.gbb885a6c ( TkG Staging )` was built
successfully under a Nix-managed shell and installed under
`~/.cache/wine-tkg/non-makepkg-builds/wine-tkg-ableton-x11-64-git`. Compared
with the stable/staging nixpkgs Wine packages it reduced some visual jank and
launched cleanly with the proper runtime wrapper, but the core bug stayed the
same:

- the proportional click drift remained
- piano-roll divider targeting was still wrong unless luck made the target line
  up with the cursor
- note-edge resize targeting was still unreliable
- tiled mode still showed jitter and clipped lower regions

This makes `wine-tkg` the best current debugging baseline, but not a functional
fix by itself.

The most useful debugging results on top of the `wine-tkg` baseline were:

- `process_mouse_message()` showed the raw physical point and the mapped point
  were identical, so the final mouse-message DPI mapping was not introducing the
  proportional drift.
- `screen_to_client()` / `client_to_screen()` then showed a consistent offset,
  not a scaling curve. In one representative trace Wine subtracted `(-156,-78)`
  from the screen point and delivered the resulting client point to Ableton.
- Deeper child-window tracing showed the child/editor window under the cursor
  was usually the expected one; wrong-child selection was not the main issue.
- The decisive mismatch was earlier in geometry state: Wine still tracked the
  main editor window at heights around `1096` while the observed X11 configure
  events for the same top-level window were `1600x900`.
- Producer-side `SetWindowPos` tracing then showed that the bad geometry first
  becomes visible in the Win32 layout path itself. For the problematic editor
  child, repeated no-size `calc_ncsize()` passes pushed `new_client.top`
  downward (`30 -> 49 -> 67 -> 85 -> 103`) even while `new_window` and
  `new_visible` stayed unchanged. Later, the larger editor child window still
  showed `new_client != new_visible` after `WM_NCCALCSIZE`, with the wrong
  geometry propagating downstream from there.
- Boundary tracing around `send_message(hwnd, WM_NCCALCSIZE, TRUE, ...)` then
  made the producer even more explicit: the bad client rect is already present
  in `params.rgrc[0]` immediately after the callback returns. For the large
  editor child, the returned client rect kept a sane left/right/bottom inset but
  inflated the top inset compared with the previous visible rect, which suggests
  the key regression may be in how Wine or Ableton computes the non-client top
  inset for that child window.
- Renderer-side tracing in `win32u/vulkan.c` later confirmed that the Vulkan
  path is not inventing a separate wrong extent. `get_surface_rect()` always
  chose `ClientRect` rather than `PresentRect` for the main editor window, and
  the swapchain/image extent matched that client rect exactly. That means DXVK
  is consuming the already-bad client geometry rather than creating the bug on
  its own.

Multiple env-gated local experiments were tried on the `wine-tkg` tree and all
failed to materially fix the bug:

- top-level `client := visible`
- server-side child hit-testing using `visible_rect`
- using `GetClientRect` instead of `GetPresentRect` for Vulkan surface sizing
- disabling `present_rect`
- using `window_rect` or `visible_rect` for client/screen origin offsets
- forcing `WM_NCHITTEST` under the target window DPI context
- freezing X11 `ConfigureNotify` origin updates
- trusting X11 `ConfigureNotify` immediately
- trusting `current_state.rect` directly for the main window
- clamping child `SetWindowPos` size requests to the parent visible size
- preserving child client rects on no-size updates
- skipping child `WM_NCCALCSIZE` on suspicious no-size updates
- forcing large child `client := visible` after `WM_NCCALCSIZE`
- direct `WM_NCCALCSIZE` boundary tracing, which showed the bad client rect is
  already returned at the callback boundary
- multiple render-side overrides (`GetClientRect` vs `GetPresentRect`, exact
  swapchain extent, no vertical surface rounding) which changed swapchain choice
  but did not materially fix the input bug

That set of negative results is useful: it rules out many easy rect/offset
substitutions and points harder at the Win32 layout/render pipeline itself,
especially the child-window `SetWindowPos` / `WM_NCCALCSIZE` path plus the final
render-surface extent selection that DXVK consumes.

## Upstream Bug Report Draft

If the investigation needs to move upstream, the current best bug report should
look roughly like this:

### Title

`Ableton Live 12 Lite under Wine shows proportional downward click offset and
 oversized top-level geometry on X11/Wayland`

### Environment

- NixOS unstable, Hyprland compositor
- PipeWire audio with JACK compatibility and WineASIO
- NVIDIA RTX 3080, proprietary driver `595.58.3`
- Ableton Live 12 Lite `12.3.6`
- Reproduced on Wine stable 11, Wine staging 11.5, and a local wine-tkg 11.6
  build
- Reproduced on Wine Wayland, Xwayland, and X11 virtual desktop modes

### Symptoms

- In windowed mode, click targets drift farther downward the lower the visible
  cursor is in the window.
- The piano-roll divider and MIDI note-edge resize targets become unusable.
- Wine Wayland also clips the bottom of the window; Xwayland removes that
  clipping but not the click-target bug.
- Popup/dialog windows often show stale black regions around or behind them.

### Strong Evidence

- DXVK logs show swapchain heights larger than the visible output height, for
  example `1908x1096` on a `1908x1032` or `1920x1080` visible region.
- `process_mouse_message()` logs show raw and mapped screen points are identical
  at the message stage, so the proportional drift is not caused by the final
  phys->mapped conversion.
- `screen_to_client()` logs show a consistent client-space offset is applied,
  but that offset corresponds to a top-level window origin that is already wrong.
- For the same main editor window, Wine tracked a geometry around
  `(156,78)-(1764,1174)` while earlier X11 `ConfigureNotify` events for that
  top-level window still reported `1600x900` visible sizes.
- Child-window selection under the cursor appeared sane in server-side tracing,
  which weakens the "wrong child hit" theory.
- `SetWindowPos` / `calc_ncsize()` tracing for the editor child showed client
  geometry drift starting before later X11 bookkeeping stages. Repeated no-size
  updates pushed the child `new_client.top` downward even when `new_window` and
  `new_visible` did not move, which suggests the Win32 layout path itself is one
  of the first concrete producer-side corruption points.

### Current Hypothesis

The bug is likely in the interaction between Wine's Win32 child layout path
(`SetWindowPos` / `WM_NCCALCSIZE`) and the later render-surface extent chosen
for the top-level/editor window. The final mouse-message coordinate transform is
consistent, but it is operating on window geometry that has already diverged
from the visible area by the time input reaches the app. Renderer-side tracing
now suggests the Vulkan path is mostly a consumer of the bad geometry, not the
original producer. The strongest current suspect is the child-window
`WM_NCCALCSIZE` result itself, especially its growing top inset relative to the
previous visible rect.

### Likely Next Inspection Targets

- `dlls/win32u/window.c`
  - `calc_winpos()`
  - `calc_ncsize()`
  - `set_window_pos()`
- `dlls/win32u/window.c`
  - the exact `WM_NCCALCSIZE` boundary: `params.rgrc[0/1/2]` before and after
    `send_message(hwnd, WM_NCCALCSIZE, TRUE, ...)`
- `dlls/win32u/window.c`
  - any local workaround that preserves the last sane visible insets when
    `WM_NCCALCSIZE` returns a drifting top inset for the large editor child
- `dlls/win32u/vulkan.c`
  - `get_surface_rect()`
  - `adjust_surface_capabilities()`
  - `win32u_vkCreateSwapchainKHR()`
- `dlls/winex11.drv/window.c`
  - only as a later consumer / tracker of already bad geometry unless the
    `WM_NCCALCSIZE` boundary tracing points back into X11 state reconstruction

### Wine-NSPA binary release

The published `Wine-NSPA 8.19` release exists as an Arch package asset and can
be downloaded directly from GitHub releases. On NixOS it is not a trivial A/B
test because:

- the package is an Arch binary package expecting FHS loaders at `/lib` and
  `/lib64`
- it depends on `librtpi.so.1`
- mixing the published Arch binaries with locally built `librtpi` under
  `steam-run` or a quick FHS env led to `allocatestack.c` glibc assertion
  failures

The binary-release path is therefore not the recommended way to continue.

### Wine-NSPA source build

The cleaner path is Wine-NSPA's own `wine-nspa-8x-git/non-makepkg-build.sh`
source build route. A 64-bit-only, X11-only test build was started from source
with an external config file under `~/.config/frogminer/wine-tkg.cfg` and a
Nix-controlled build shell.

That source build is demonstrably viable, but it has already become a local
porting effort for this toolchain. The following classes of fixes were required
just to move the build forward:

- NixOS portability fixes for hardcoded `/usr/bin/perl` helpers in the Wine /
  Wine-staging preparation scripts
- GCC 15 compatibility fixes in patched sources such as
  `dlls/kernelbase/process.c`
- multiple `bool` / `true` / `false` identifier collisions in older patched
  code, including `dlls/win32u/sysparams.c`, `programs/winhlp32/macro.h`, and
  `dlls/http.sys/http.c`
- compatibility fixes for Wine's stricter `CONTAINING_RECORD` macro in patched
  code such as `dlls/combase/string.c`
- linker and compiler flag fixes for `loader/wine64-preloader` to avoid modern
  PIE-related relocation failures

At the time of writing, the source build has gone deep into compilation but is
still surfacing additional old-patch-vs-modern-toolchain failures. Treat it as
an ongoing source-port exercise, not a quick runner download.

## Roadmap

The most useful next steps, in order, are:

1. Keep the current system-level NixOS and Home Manager plumbing as-is. The
   remaining problem is no longer in the host wiring.
2. Choose whether to continue custom Wine work on `Wine-NSPA` or pivot to a
   cleaner custom-Wine base such as `wine-tkg`. The current evidence suggests
   Wine-NSPA is viable only through continued source-porting work.
3. If continuing with Wine-NSPA, keep the current strategy:
   64-bit only, X11-only build, same copied prefix for A/B testing, and patch
   forward one blocker at a time until a usable `wine64` runner exists.
4. If pivoting to `wine-tkg`, try to get a modern custom build first before
   spending more time on the older Wine-NSPA tree. The current GUI symptom set
   looks more like an upstream/window/input bug than an RT-scheduling bug.
5. When a new custom Wine build is available, test it against a cloned prefix
   rather than the primary working prefix so custom-build regressions stay
   isolated.
6. Keep local ad hoc wrappers and temporary test EXEs out of the declarative
   repo until one approach actually improves the symptom cluster.

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
