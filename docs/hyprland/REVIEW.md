# Hyprland Review

## Scope

This review compares the current repo configuration against current Hyprland wiki guidance, with emphasis on:

- config organization
- window and layer rule syntax
- keybind conventions
- multi-monitor and multi-GPU setup
- plugin loading
- idle and lock flow

Primary wiki sources:

- Configuring Hyprland: <https://wiki.hypr.land/0.42.0/Configuring/Configuring-Hyprland/>
- Keywords (`source`, `exec-once`, `env`): <https://wiki.hypr.land/0.52.0/Configuring/Keywords/>
- Binds: <https://wiki.hypr.land/0.49.0/Configuring/Binds/>
- Monitors: <https://wiki.hypr.land/Configuring/Monitors/>
- Window Rules: <https://wiki.hypr.land/0.53.0/Configuring/Window-Rules/>
- Environment variables: <https://wiki.hypr.land/Configuring/Environment-variables/>
- Multi-GPU: <https://wiki.hypr.land/0.51.0/Configuring/Multi-GPU/>
- Using plugins: <https://wiki.hypr.land/Plugins/Using-Plugins/>
- hypridle: <https://wiki.hypr.land/hyprland-wiki/pages/Hypr-Ecosystem/hypridle/>
- hyprlock: <https://wiki.hypr.land/0.49.0/Hypr-Ecosystem/hyprlock/>
- Nvidia: <https://wiki.hypr.land/Nvidia/>

## Overall Assessment

The live Hyprland config is broadly aligned with current wiki guidance:

- it uses a sourced multi-file layout
- it already uses current `windowrule` and `layerrule` forms
- it uses a wiki-recommended fallback monitor rule
- its `hypridle` lock flow is very close to the wiki example

The biggest gaps are not parser syntax problems. They are:

1. laptop multi-GPU device selection uses unstable `/dev/dri/cardN` paths
2. the repo contains a few stale or non-live modules that weaken the otherwise clean modular layout
3. some keybind and rule patterns could be updated to match newer wiki conventions more closely

## Deprecated Syntax

No obviously deprecated Hyprland syntax was found in the active files.

- The window rules use current anonymous `windowrule = ...` syntax and current named `windowrule {}` blocks.
- The layer rules use current `layerrule` syntax and named `layerrule {}` blocks.
- The monitor config uses classic `monitor = ...` lines, which are still current. The wiki documents `monitorv2` as an alternative syntax, not a required migration.

The one legacy issue is organizational, not parser-level:

- `THEMING.md` still describes `pluginsettings.conf` as the live plugin theming file, but the active config graph sources `plugins.conf` instead.

## What Already Matches The Wiki Well

### Multi-file organization

The wiki recommends splitting config with `source = ...` and notes that parsing is linear. The repo already does this correctly in `hyprland.conf`, with host and generated inputs loaded before appearance, plugins, rules, and startup commands.

### Current rule syntax

The live rules file already matches the current rule model from the wiki:

- props use `match:*`
- effects use the newer effect names such as `float on`, `center on`, `size 900 600`, `blur on`, and `ignore_alpha`
- named rules are used where block syntax is clearer

There is no lingering `windowrulev2` split or old `windowrule = RULE,WINDOW` form in the active config.

### Monitor fallback pattern

The wiki explicitly recommends `monitor = , preferred, auto, 1` for "random monitor" hotplug behavior. Both host monitor files already use that rule as the catch-all fallback.

### Idle and lock sequence

The wiki `hypridle` example uses:

- `lock_cmd = pidof hyprlock || hyprlock`
- `before_sleep_cmd = loginctl lock-session`
- `after_sleep_cmd = hyprctl dispatch dpms on`

The repo uses exactly that pattern. The listener progression of dim, lock, DPMS off, and suspend also follows the same intended shape.

### Nvidia desktop basics

For the desktop host, the wiki's Nvidia page calls out:

- `env = LIBVA_DRIVER_NAME,nvidia`
- `env = __GLX_VENDOR_LIBRARY_NAME,nvidia`
- `env = ELECTRON_OZONE_PLATFORM_HINT,auto`
- `env = NVD_BACKEND,direct` when using `nvidia-vaapi-driver`

Those are already present in the desktop-specific env fragment.

## Recommended Improvements

### 1. Fix laptop `AQ_DRM_DEVICES` path stability

Current laptop env:

- `env = AQ_DRM_DEVICES, /dev/dri/card2:/dev/dri/card1`

Current wiki guidance is explicit that `/dev/dri/cardN` is not stable across boots and should not be treated as a reliable identifier for a particular GPU. The Multi-GPU page recommends either:

- using `/dev/dri/by-path/...` to discover the mapping, or
- creating stable udev symlinks such as `/dev/dri/amd-igpu`

This is the most concrete config issue in the current setup. On a hybrid laptop, it is also the most likely item to cause confusing breakage after boot-order changes or driver changes.

### 2. Treat stale modules as architecture drift

The live modular story is good, but the repo graph has drifted:

- `config/hypr/pluginsettings.conf` is no longer sourced by `hyprland.conf`
- `THEMING.md` still treats `pluginsettings.conf` as the live plugin theming file
- `config/hypr/monitors.conf` exists, but `home/default.nix` does not select it for either known host

The wiki's sourced-file model works best when every module in the tree is either:

- clearly active, or
- clearly documented as generated, host-specific, or archival

Right now `plugins.conf` is the live file, while `pluginsettings.conf` is a stale parallel version. Likewise, `config/hypr/monitors.conf` reads like a base file, but the actual host selection bypasses it. Consolidating or documenting those files would make the modular layout easier to trust.

### 3. Separate environment fragments from host-only startup when possible

`hosts/desktop/env.conf` contains both:

- environment variables
- `exec-once = solaar config "MX Master 2S" smart-shift 50`

This works because Hyprland's parser accepts both keywords in the same sourced file, but it blurs module purpose. The wiki's organization advice is light, but its source-based model assumes file names and sourced fragments stay semantically obvious.

If this repo keeps growing, a dedicated host-specific startup fragment would make the config easier to audit than putting an autostart command into `env.conf`.

### 4. Harden rule matches that depend on exact full-match regexes

The current Window Rules page notes that regexes fully match window values and that rules are evaluated top to bottom.

Most of the current rules use plain exact strings, which is valid, but a few cases are easy to make brittle:

- `match:title Zoom Meeting`
- browser-extension popup classes
- portal or KDE tool classes that may vary by packaging or version

This is not deprecated syntax, but it is worth checking with `hyprctl clients` and then deciding whether each rule should be:

- an exact anchored match such as `^Zoom Meeting$`, or
- a broader regex such as `.*Zoom Meeting.*`

The wiki's current guidance makes this especially relevant because older substring-style assumptions no longer hold.

### 5. Use bind descriptions and bind flags where they help

The current binds are valid, but they do not take advantage of newer bind features that the wiki now documents:

- `bindd` descriptions for discoverability through `hyprctl binds`
- `binde` for repeat-on-hold actions
- `bindl` for actions that should still work while input is inhibited

Concrete cases where this may help:

- volume and brightness controls if hold-to-repeat is desirable
- lock-adjacent or hardware-key behavior if some actions should remain available while locked
- documenting Quickshell IPC binds without needing to read the file directly

This is an ergonomics improvement, not a correctness issue.

### 6. Consider named rules for anything you may want to toggle live

The wiki notes that only named rules can be enabled, disabled, or changed dynamically with `hyprctl keyword`.

The current config already uses named blocks for:

- `no-hyprbars-on-tiled`
- Vicinae layer rules

That is good. If Quickshell blur rules or other overlay rules are likely to be toggled live later, they would benefit from being turned into named `layerrule {}` blocks instead of commented anonymous examples.

## Hardware-Specific Notes

### Hybrid laptop

The wiki's Multi-GPU guidance says laptops should generally keep the integrated GPU first in `AQ_DRM_DEVICES`, which this repo already does conceptually.

The gaps are:

- use stable GPU paths, not `cardN`
- if monitors attached to the Nvidia GPU are broken or extremely slow, the Nvidia page suggests trying `AQ_FORCE_LINEAR_BLIT=0`

That second point is conditional. It is not something the wiki recommends unconditionally, but it is the specific knob the wiki now points to for hybrid-monitor problems.

### Dedicated Nvidia desktop

The desktop env fragment is already close to the wiki's expected Nvidia setup.

Potential follow-up only if relevant to the actual machine:

- The Nvidia wiki now recommends the open kernel modules for newer Turing/Ampere-and-later cards when supported.
- If Electron/CEF apps still flicker, the wiki also points to app flags for `WaylandLinuxDrmSyncobj`, not only `ELECTRON_OZONE_PLATFORM_HINT`.

Those are situational, not mandatory config gaps.

### `uwsm` caveat

The Environment Variables page now says that `uwsm` users should avoid putting environment variables in `hyprland.conf` and instead use:

- `~/.config/uwsm/env`
- `~/.config/uwsm/env-hyprland`

This only matters if the session is actually launched through `uwsm`. If not, the current `env.conf` layout remains fine.

## Plugins

The wiki strongly recommends `hyprpm` for plugin management and documents:

- `permission = /usr/(bin|local/bin)/hyprpm, plugin, allow`
- `exec-once = hyprpm reload`

This repo intentionally does something else:

- plugin `.so` files come from a Nix-provided `HYPR_PLUGIN_DIR`
- `plugins.conf` loads them directly by absolute path

That is a valid manual-loading approach and makes sense for a pinned Nix setup. It is a divergence from the wiki's preferred operational path, not a defect by itself.

## Idle And Lock

The `hypridle` and `hyprlock` setup is one of the stronger parts of the current config.

Aligned with the wiki:

- `hypridle` startup from Hyprland autostart
- standard lock-before-sleep and DPMS-on-after-sleep behavior
- `hyprlock` as the dedicated lock command
- widget `monitor =` left empty so the lock UI applies to all monitors

Optional wiki-exposed knobs not currently used:

- `unlock_cmd`
- `ignore_dbus_inhibit`

Those only matter if there is a real need for post-unlock hooks or if D-Bus idle inhibitors are getting in the way.

## Bottom Line

The live Hyprland config is already using current Hyprland concepts and does not need a syntax migration.

The most valuable improvements are:

1. replace laptop `AQ_DRM_DEVICES` `cardN` paths with stable device paths
2. remove or clearly mark stale modules such as `pluginsettings.conf` and the unused base `config/hypr/monitors.conf`
3. tighten a few rule matches and optionally adopt `bindd` / `binde` / `bindl` where they improve maintainability or input behavior

Everything else is mostly incremental polish rather than a sign that the config is behind the wiki.
