# Hyprland

## Intent

- Hyprland is configured in Lua. hyprlang `.conf` was deprecated upstream in
  0.55 and the Lua API has no `source` escape hatch, so everything in the
  graph — generated and host-specific files included — is Lua. `hypridle.conf`
  and `hyprlock.conf` are separate hyprlang apps, outside the graph.
- `config/hypr/hyprland.lua` requires a fixed ordered list of modules; the
  order is contract — later files may override earlier ones, and runtime
  override files must come after the static/host fragments they override.
- Generated files are pure data tables (`return { ... }`) with no side
  effects; the hand-written module that requires one applies it and must
  tolerate the file being absent or empty (empty = "no overrides", which is
  what `desktopctl ... clear` writes).
- Three file classes are not in the repo and generated/selected at runtime:
  - theming targets write `colors.lua`, `appearance-theme.lua`,
    `cursor-theme.lua` (plus a hyprlang `colors.conf` kept only for hyprlock);
  - `desktopctl hypr` writes `input-runtime.lua`,
    `animations-override-data.lua`, `keybinds-override-data.lua`;
  - Home Manager selects `monitors.lua`, `env-host.lua`, `input-devices.lua`,
    and `autostart-host.lua` from `hosts/<host>/` via the `host.hyprland.*`
    facts, with fallbacks that must boot on any future host. Shared session
    env lives in the static `env.lua`; host files carry only GPU env and
    host-only settings.
- Ownership: the theming pipeline and desktopctl never edit base config;
  Quickshell talks to Hyprland only through `hyprctl`/IPC and transient
  `systemd-inhibit` holds, never config writes; the daemon owns `hyprsunset`
  ([[sun-schedule]]); the wallpaper target owns `awww img` while
  `autostart.lua` owns `awww-daemon` startup.
- Hyprland is pinned to a release tag, and hyprexpo comes from the maintained
  `sandwichfarm/hyprexpo` fork as a repo-local package
  (`pkgs/hyprland-plugins/hyprexpo/`) because the official plugin flake
  removed it. Advance Hyprland only when the fork has a matching release, and
  re-pin `hyprland-plugins` (hyprbars) when it publishes a matching tag.

## Quirks

### The config verifier lies about plugin keys
Static config verification reports false errors on plugin-owned keys. The only
trustworthy check for config changes is a nested Hyprland session.

### Workspace pins exclude their IDs even when the pinned monitor is absent
`CMonitor::findAvailableDefaultWS` skips every workspace ID whose
`monitor:` rule selector the connecting output does not match — whether or not
that monitor exists. With `hosts/laptop/monitors.lua` pinning 1–10 to the BenQ
by EDID description, an undocked laptop login lands on workspace 11, which no
keybind can reach; the first window of the session gets stranded there and the
evidence self-destructs once the empty workspace is destroyed. Fixed by the
`desktopctl daemon` monitor watcher running `hypr::reclaim_workspaces` on
connect and on monitor add/remove; reproduce the raw bug with
`hyprctl output create headless`. Every enabled monitor always has an active
workspace — Hyprland has no "workspace-less extension display" concept, which
is why the pinning approach exists at all.

### D-Bus-activated windows can inherit stale workspace tokens
Hyprland injects `HL_INITIAL_WORKSPACE_TOKEN` into exec children. If session
startup copies that (or `XDG_ACTIVATION_TOKEN`/`DESKTOP_STARTUP_ID`) into the
D-Bus/systemd activation environment or a long-lived launcher daemon, portal
pickers and D-Bus-activated apps open on workspace 1 forever after.
`config/hypr/autostart.lua` scrubs these tokens before the environment sync —
keep it that way.

### Portal services need the imported graphical-session environment
Portal backends started before `WAYLAND_DISPLAY`/`XDG_CURRENT_DESKTOP` are
imported into the user manager come up broken (first-login file pickers fail
while later restarts work). The first `exec-once` in `autostart.lua` imports
the env, scrubs tokens, starts `graphical-session.target` and the portal
services explicitly; `exec-shutdown` stops the target. See [[nix]] for the
portal backend selection itself.

### Files required before `plugins.lua` cannot use plugin keywords
The graph loads linearly and `input-devices.lua` comes before `plugins.lua`,
so plugin-owned gesture/dispatcher keywords there fail as unknown. The laptop
touchpad overview gesture therefore uses the core `gesture` keyword with a
`dispatcher` action calling `hyprexpo:expo toggle`; `keybinds.lua` loads after
plugins and can bind the plugin dispatcher directly.

### Host-selected fragments must be git-tracked before rebuilding
The flake source only materializes files Git knows about. A new untracked file
under `hosts/*/` produces a Home Manager symlink to a path that does not exist
in the store source — `hyprctl configerrors` reports it inaccessible even
though it's sitting in the working tree. Track the file, rebuild again.

### Shared input settings don't beat per-device blocks
`desktopctl hypr input set` updates the shared `input` defaults via
`input-runtime.lua`, but per-device blocks in `hosts/*/input-devices.lua`
(the Logitech sensitivity tuning) still win for those devices. A mouse that
ignores the Mouse settings page is hitting a device block, not a bug.

### Window-rule matches drift
hyprpolkitagent sets no app_id (empty class), so its float rule matches on
title `Hyprland Polkit Agent`; several other rules match exact classes/titles
(`Zoom Meeting`, incognito patterns, Discord's updater). After bumping any of
these packages, verify with `hyprctl clients` while the window is open.

### hyprlock's fingerprint auth is enabled on every host on purpose
The shared `hyprlock.conf` enables fingerprint auth; only the laptop has
fprintd. The desktop logs an fprintd D-Bus error at unlock and degrades to
password — that error is noise, and a host-split of hyprlock.conf is
deliberately not done.

### MX Master 2S smart-shift caps at 50
Solaar exposes `smart-shift` on a 0–50 scale for this device; 50 *is* the
always-ratcheted value, and higher values fail. The laptop autostart also sets
`scroll-ratchet Ratcheted` while the desktop doesn't (owner question pending,
see `TODO.md`).

### `hyprland-guiutils` needs explicit Pango cflags on this input lock
The locked `hyprgraphics` public headers include Pango, but the nested
`hyprland-guiutils` package doesn't request Pango's pkg-config cflags —
`nrs` fails with `pango/pango-font.h: No such file or directory`.
`system/configuration.nix` (`patchedHyprlandGuiutils`) carries the workaround;
re-test a plain build before removing it after input updates.

Related: [[nix]], [[nvidia]], [[theming]], [[quickshell]], [[desktopctl]]
