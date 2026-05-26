# Nix Quirks

## `texlive.combined.scheme-medium` recurses on this nixpkgs revision
**Symptom:** Evaluation blows up if the TeX Live package set pulls in `scheme-medium`.
**Cause:** On this pinned nixpkgs revision, `scheme-medium` pulls `asymptote` through `collection-binextra` and the evaluation recurses.
**Status:** Workaround in place
**Resolution:** `home/default.nix` builds the shared TeX Live environment with `scheme-small` plus explicit extras like `latexmk` and `tikz-cd`.

## The shared `kevin` account keeps a checked-in bootstrap password on purpose
**Symptom:** Audits keep flagging `users.users.kevin.initialPassword` in `system/configuration.nix` as if it were an accidental secret leak.
**Cause:** The shared baseline intentionally keeps a reproducible local bootstrap login path for fresh installs, while SSH password auth remains disabled separately in the same shared system module.
**Status:** Intentional bootstrap state
**Resolution:** Treat the checked-in `initialPassword` as deliberate bootstrap behavior, not as undocumented drift. If the bootstrap path changes, document the replacement in this domain instead of silently removing it and leaving future agents to guess whether it was accidental.

## Stock `services.fstrim` can touch the Windows NVMe through a shared EFI mount
**Symptom:** A weekly `fstrim` run trims `/boot/efi` even though the goal is only to discard unused blocks on the Linux filesystem.
**Cause:** The stock NixOS `services.fstrim.enable = true` unit trims every mounted filesystem it sees in `/etc/fstab` and `/proc/self/mountinfo`. On dual-boot hosts that mount a shared EFI system partition from the Windows drive at `/boot/efi`, that includes the Windows NVMe.
**Status:** Workaround in place
**Resolution:** `system/services.nix` now defines a custom `fstrim-root.service` plus `fstrim-root.timer` instead of enabling `services.fstrim`. Keep the trim target pinned to `/` unless you explicitly want discard to reach additional mounted filesystems too.

## Optimizing low-level libraries explodes the rebuild graph
**Symptom:** A small `-march` overlay on `zstd` or `lz4` turns into huge rebuild cascades.
**Cause:** Those libraries sit low in shared dependency chains, pulling rebuilds through `libarchive`/`cmake`/`llvm` or `systemd`/`nix`.
**Status:** Workaround in place
**Resolution:** `overlays/native-optimized.nix` deliberately leaves `zstd` and `lz4` unoptimized unless a separate opt-in path is added later.

## Native-optimized derivations must carry host-specific `requiredSystemFeatures`
**Symptom:** Desktop and laptop can otherwise build different native outputs at the same store path even when the literal optimization flags match.
**Cause:** `-march=native` and `target-cpu=native` depend on the builder CPU, so the literal flag strings are not enough to distinguish safe cache/scheduler boundaries across hosts.
**Status:** Workaround in place
**Resolution:** `system/native-optimizations.nix` and `overlays/native-optimized.nix` tag native derivations with `requiredSystemFeatures = [ "native-optimized-<host>" ]`, and `system/configuration.nix` advertises only the current host's native feature through `nix.settings.system-features` while `enableNativeOptimizations` is enabled.

## Host `system-features` must not advertise `native-optimized-*` unconditionally
**Symptom:** Stock `x86_64-linux` builds stop behaving like generic cacheable builds when a host always claims a native-only feature.
**Cause:** Builder capability leakage changes scheduling and cacheability even when the optimization overlay is off.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` appends `native-optimized-${host.name}` only while `enableNativeOptimizations` is enabled.

## Flake-input package overrides share the native helper path
**Symptom:** Hyprland, Hyprland plugins, and `hyprqt6engine` would otherwise diverge from the native optimization policy used for the selected nixpkgs packages.
**Cause:** Those derivations come from flake inputs or local overrides rather than the nixpkgs package set targeted by `overlays/native-optimized.nix`. `hyprexpo` is now a repo-local package under `pkgs/hyprland-plugins/hyprexpo/default.nix`, but it follows the same helper path as the flake-input Hyprland packages.
**Status:** Intentional design
**Resolution:** `system/configuration.nix` and `home/default.nix` both import `system/native-optimizations.nix` directly, so the remaining flake-input packages carry the same `-O3 -march=native` / `target-cpu=native` flags and per-host `requiredSystemFeatures` tag as the overlay-managed nixpkgs packages.

## Vicinae server autostart uses Hyprland only
**Symptom:** Running Vicinae through both the Home Manager service and Hyprland `exec-once = vicinae server` starts redundant background paths for the same launcher.
**Cause:** nixpkgs already packages `vicinae`, so the launcher can be installed directly without also enabling the upstream Home Manager service module. This repo still needs the Vicinae server to be present during the session, but it should have a single owner.
**Status:** Hyprland-owned server startup
**Resolution:** `home/default.nix` still imports `vicinae.homeManagerModules.default` so the option remains available if needed later, but `home/packages.nix` installs `pkgs.vicinae` through `vicinaePkg` and does not enable `services.vicinae`. `config/hypr/autostart.conf` starts `vicinae server` directly, while `SUPER+R` / `vicinae open` only opens the already-running launcher.

## Snappy Switcher is simpler as a local package than as a flake input
**Symptom:** The previous setup routed Snappy Switcher through a dedicated upstream flake input even though the package recipe was tiny and the only repo-specific behavior was a small local patch for current-workspace filtering.
**Cause:** Upstream ships a simple `mkDerivation` in its flake rather than a package already available in nixpkgs. Keeping it as a flake input added another lockfile node and another special-case package path without buying much.
**Status:** Simplified to a local package
**Resolution:** `overlays/local-packages.nix` now exposes `pkgs.snappy-switcher` from `pkgs/snappy-switcher/default.nix`, which fetches the upstream source snapshot directly and applies `patches/snappy-switcher/workspace-scope-filter.patch`. This keeps the current-workspace filtering behavior while removing the separate `snappy-switcher` flake input and its extra override plumbing.

## Stock packages can still miss cache hits through optimized wrapper inputs
**Symptom:** A package that is not listed in `overlays/native-optimized.nix` still rebuilds locally and gets a different derivation path from plain nixpkgs.
**Cause:** A global overlay rewrites the shared `pkgs` set. Once a package inside that set is replaced with a native-optimized variant, any consumer that depends on it in build inputs, runtime closures, or wrapper paths also gets a new derivation path.
**Status:** Workaround in place
**Resolution:** Do not apply the native overlay to the global `pkgs` set. `system/configuration.nix` and `home/default.nix` now keep the shared package set stock and instead create local `optimizedPkgs = pkgs.appendOverlays [ optimizedPackages.overlay ]` aliases only for the top-level packages that are intentionally rebuilt with host-native codegen. That keeps unrelated packages such as `codex`, `bitwarden-desktop`, and `adw-gtk3` on the stock cache path.

## Native-tagged rebuilds need a client-side bootstrap during the switch that enables them
**Symptom:** `nixos-rebuild switch` can fail before activation with `missing system features` even though the evaluated target config already includes `native-optimized-<host>` in `nix.settings.system-features`.
**Cause:** The build runs through the currently active Nix daemon, and that daemon does not start advertising the new host-native feature until after the switch finishes and the rebuilt `nix.conf` is live.
**Status:** Workaround in place
**Resolution:** `home/shell.nix` makes the `nrs` wrapper pass the target `system-features` list directly to `sudo nixos-rebuild switch` whenever native optimizations are enabled. That bootstraps the native-tagged derivations through the current daemon. Plain non-root `nix build --option system-features ...` is not sufficient here because `system-features` is a restricted setting for untrusted users.

## Physical hosts use the stock nixpkgs kernel package set
**Symptom:** Custom physical-host kernel changes can break boot before persistent journald captures useful logs, as happened with desktop generation 73.
**Cause:** The old shared `system/native-kernel-packages.nix` path rebuilt `linux_6_18` with Clang/ThinLTO/native flags plus CachyOS BORE and BBR3 patches. That boot-critical custom closure was harder to trust than the cached nixpkgs kernel package set.
**Status:** Stock kernel path in place
**Resolution:** `system/physical-host.nix` now sets `boot.kernelPackages = pkgs.linuxPackages`, and the repo no longer carries `system/native-kernel-packages.nix`. Keep low-risk runtime policy in `boot.kernelParams`, `boot.kernel.sysctl`, and systemd services instead of reintroducing a shared CachyOS/native kernel rebuild path.

## Physical-host working-set protection uses MGLRU `min_ttl_ms`
**Symptom:** Desktop and laptop now ask for LE9/LE10-style working-set and file-cache protection, but the active tuning path is not an obvious `vm.*_kbytes` sysctl block in the host modules.
**Cause:** The shared kernel config keeps `LRU_GEN=y` and `LRU_GEN_ENABLED=y`, and `system/physical-host.nix` now applies the runtime policy through `systemd.services.mglru-tuning`, which writes `y` to `/sys/kernel/mm/lru_gen/enabled` and `1000` to `/sys/kernel/mm/lru_gen/min_ttl_ms`. The repo intentionally uses MGLRU's own thrash-prevention knob as the active protection path.
**Status:** Intentional design
**Resolution:** Tune `systemd.services.mglru-tuning.script` in `system/physical-host.nix` if you want a different pressure-relief threshold, or remove that service if you want stock MGLRU behavior. Do not assume the older LE9 `vm.anon_min_kbytes` / `vm.clean_low_kbytes` / `vm.clean_min_kbytes` knobs are the active control surface in this repo.

## Desktop kernel trim is disabled until it is boot-validated
**Symptom:** Generation 73 on the desktop failed to boot far enough to leave a persistent journal entry, while generation 72 booted normally.
**Cause:** The failed generation differed from the working generation in the kernel/initrd/NVIDIA-open closure. The desktop-specific PREEMPT_FULL and dead-subsystem Kconfig trim plus forced initrd module list made that closure harder to trust because an early kernel or stage-1 failure would not be debuggable from the normal journal.
**Status:** Avoided for boot stability
**Resolution:** `hosts/desktop/system.nix` no longer adds desktop-only `boot.kernelPatches` or forces `boot.initrd.availableKernelModules`; it stays on the shared physical-host kernel config and a normal merged initrd module list. Reintroduce desktop Kconfig trimming only as a separately tested change, and verify a real desktop boot before keeping it.

## Physical hosts disable CPU vulnerability mitigations on purpose
**Symptom:** `lscpu`, `/sys/devices/system/cpu/vulnerabilities/*`, or boot logs report that Spectre, Meltdown, and related CPU side-channel mitigations are disabled on the laptop and desktop.
**Cause:** `system/physical-host.nix` now sets `boot.kernelParams = [ "mitigations=off" "transparent_hugepage=madvise" ]` on the shared physical-host gate.
**Status:** Intentional exception
**Resolution:** Keep the parameter on the shared physical-host baseline only if the performance tradeoff is intentional. Remove that physical-host kernel param in `system/physical-host.nix` to restore the kernel's default mitigation policy.

## Physical-host local builds allow limited derivation concurrency on purpose
**Symptom:** Local Nix builds on desktop and laptop can build up to two derivations at once instead of fully serializing the local queue.
**Cause:** `system/physical-host.nix` now sets `nix.settings.max-jobs = 2` on the shared physical-host gate. The repo does not set `cores`, so each build can still use its package-specific default parallelism while Nix limits the number of concurrent derivations.
**Status:** Intentional exception
**Resolution:** Keep the physical hosts on `max-jobs = 2` if the machine benefits from some overlap between smaller builds. If heavy builds still create too much memory pressure, either lower `max-jobs` again or add package-specific parallelism caps instead of globally pinning all local builds.

## Narrow unfree predicates must cover transitive module closures, not just package lists
**Symptom:** Replacing `allowUnfree = true` with a small name allowlist still fails evaluation on packages that are not listed directly in `home.packages` or `environment.systemPackages`.
**Cause:** NixOS and Home Manager evaluate the full module graph. Unfree packages can enter indirectly through options such as `fonts.packages`, `programs.steam.*`, or CUDA-enabled dependency closures.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now uses `allowUnfreePredicate`, but its allowlist must include both the directly selected apps and the extra unfree package names already required by the current system closure, such as `sf-pro`, `symbola`, `steam-unwrapped`, and the CUDA userspace packages pulled in by existing desktop packages.

## Apple rotates `SF-Pro.dmg` behind a stable URL
**Symptom:** `nixos-rebuild` fails while building `sf-pro` with a fixed-output derivation hash mismatch on `SF-Pro.dmg`.
**Cause:** The Apple download URL in `overlays/local-packages.nix` stays the same while the bytes behind it change, so the repo-local `fetchurl` pin eventually stops matching upstream.
**Status:** Workaround in place
**Resolution:** Refresh the repo-local `sf-pro` pin in `overlays/local-packages.nix` by updating both the local version date and `src.hash` to the current Apple DMG, then retry the rebuild.

## Current SF Pro DMG exposes `Payload~` as a plain cpio archive
**Symptom:** `nixos-rebuild` fails while building `sf-pro` with `7z` aborting on `Payload~` with `ERROR: E_FAIL`.
**Cause:** Apple's current `SF Pro Fonts.pkg` no longer needs a second gzip-style unpack step after the `.pkg` is extracted. On the currently locked `SF-Pro.dmg`, `Payload~` is already a plain cpio archive.
**Status:** Workaround in place
**Resolution:** `overlays/local-packages.nix` now defines a local `pkgs.sf-pro` derivation that fetches the pinned Apple DMG directly and extracts `Payload~` with `cpio` when possible, falling back to `7z` for older layouts. `system/configuration.nix` installs that local package instead of the upstream `apple-fonts.nix` derivation.

## Generic `SF Pro` can look soft on Linux without extra fontconfig tuning
**Symptom:** UI text that explicitly requests `SF Pro`, especially bold labels at normal desktop sizes, can look fuzzier than expected even though the correct font package is installed.
**Cause:** The shared NixOS fontconfig defaults use grayscale antialiasing (`10-sub-pixel-none.conf`), and Apple's font package also exposes a catch-all `SF Pro` variable face that fontconfig can choose before the `SF Pro Text` optical cut that is better suited to small UI sizes.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now sets `fonts.fontconfig.subpixel.rgba = "rgb"` and adds a local fontconfig rule that prepends `SF Pro Text` whenever apps request the generic `SF Pro` family. If a monitor shows color fringes after rebuild, switch that `rgba` value to the panel's real order (`bgr`, `vrgb`, or `vbgr`).

## Automatic timezone still depends on GeoClue resolving a location
**Symptom:** `timedatectl` keeps the previous timezone after travel even though `services.automatic-timezoned` is enabled.
**Cause:** `system/services.nix` lets GeoClue own locality and `automatic-timezoned` only applies a timezone after GeoClue returns coordinates. If GeoClue cannot see Wi-Fi networks, the BeaconDB lookup times out, or the agent/app authorization path is broken, the timezone service has no new location to apply.
**Status:** Expected limitation
**Resolution:** Check `where-am-i` under the user session and `journalctl -u geoclue.service` before debugging `automatic-timezoned` itself. Locale and keyboard layout remain static through `i18n.defaultLocale = "en_US.UTF-8"` and `console.keyMap = "us"`; only timezone is dynamic.

## Home Manager packages do not register system-scoped helpers
**Symptom:** A GUI app installed only through `home.packages` starts, but its root helper never appears on the system bus and no polkit prompt is triggered.
**Cause:** Home Manager installs packages into the user profile, outside the NixOS system path and `services.dbus.packages` set that expose `share/dbus-1/system-services` files and link `share/polkit-1/actions` for system-wide activation.
**Status:** Workaround in place
**Resolution:** Install those apps through NixOS modules or `environment.systemPackages`. `system/configuration.nix` now enables `programs.partition-manager` so `kpmcore` is registered for both D-Bus activation and polkit, and `bitwarden-desktop` stays in `environment.systemPackages` for the same reason.

## Bambu Studio cloud login uses a temporary AppImage wrapper
**Symptom:** Completing Bambu Lab login closes the prompt but leaves Bambu Studio appearing logged out, or the browser OAuth flow cannot return to Bambu Studio through the local callback.
**Cause:** The current locked nixpkgs `bambu-studio` build predates NixOS/nixpkgs#522161, which fixes the source-built package's cloud-auth runtime. Backporting that patch locally still forces a large Bambu Studio C++ rebuild; on the current host it is slow enough to be a poor routine workaround.
**Status:** Temporary AppImage overlay in place
**Resolution:** `overlays/local-packages.nix` replaces `pkgs.bambu-studio` with the official upstream Ubuntu 24.04 `BambuStudio_ubuntu-24.04-v02.06.00.51-20260417160415.AppImage`, wrapped through `appimageTools.wrapType2`. The wrapper installs the upstream desktop file/icon, adds a small `$out/bin/bambu-studio-desktop` shell-parent launcher, rewrites the desktop file to that absolute launcher path, adds `glib-networking`, `webkitgtk_4_1`, GStreamer plugins, `libsecret`, and explicit CA/GIO/WebKit/font environment so the login webview and callback path work in the NixOS session without a source rebuild. The shell parent is required for Vicinae's detached Qt launcher; launching the AppImage/FHS wrapper directly can return success and then exit immediately. Do not switch back to the Fedora AppImage on this nixpkgs pin: it links removed WebKitGTK 4.0 and `libsoup-2.4.so.1`, which would require an EOL libsoup 2 insecure-package exception. Remove the overlay after the flake's `nixpkgs` input includes NixOS/nixpkgs#522161 or an equivalent upstream fix and the source-built package is confirmed to log in. If the AppImage opens with language/locale errors after running the old package, delete the stale `language` key from `~/.config/BambuStudio/BambuStudio.conf` or remove that config directory after backing up any needed printer/profile state.

## SDDM cannot read wallpapers from the locked-down home directory directly
**Symptom:** Pointing `where_is_my_sddm_theme` straight at a wallpaper under `/home/kevin/...` leaves the greeter background blank even though the same path works inside the user session.
**Cause:** The shared `kevin` home directory is mode `0700`, so the pre-login SDDM user cannot traverse into the repo checkout or other home-owned wallpaper paths.
**Status:** Workaround in place
**Resolution:** `desktopctl/src/theme/targets/where_is_my_sddm_theme.rs` stages the selected wallpaper into `/tmp/desktopctl-where-is-my-sddm-theme/background`, and `system/services.nix` copies that staged file into the root-owned `/var/lib/desktopctl/where-is-my-sddm-theme/background` path that SDDM reads. Keep the SDDM theme pointed at the `/var/lib` copy rather than a home-directory source path.

## Qt plugin paths break if you only point `QT_PLUGIN_PATH` at hyprqt6engine
**Symptom:** Qt and KDE apps can pick up the generated palette but still fall back to partially unstyled widgets or miss Kvantum styling, especially in D-Bus/systemd-activated helpers such as `xdg-desktop-portal-kde`.
**Cause:** `hyprqt6engine` installs under `lib/qt-6/`, outside the standard `/lib/qt-*/plugins` roots. A hand-written `QT_PLUGIN_PATH=${hyprqt6engine}/lib/qt-6` exposes the Hyprland platform theme itself but hides profile-installed plugins like `qt5ct`, `qt6ct`, and `libkvantum.so` unless NixOS also wires the normal profile-relative plugin directories.
**Status:** Workaround in place
**Resolution:** `system/configuration.nix` now enables NixOS `qt.enable`, exports `QT_QPA_PLATFORMTHEME=hyprqt6engine`, keeps the hyprqt6engine root on `QT_PLUGIN_PATH`, and installs `qt5ct`, `qt6ct`, and Kvantum system-wide so both regular apps and user services resolve the same plugin set.

## Neuwaita needs KDE color-scheme metadata for symbolic icon recoloring
**Symptom:** KDE apps keep their custom folder/file icons from Neuwaita, but toolbar and sidebar action icons can stay black on dark themes, or Dolphin's default blue folders can look like oversized Breeze fallbacks.
**Cause:** KIconThemes only rewrites Breeze SVG `current-color-scheme` styles when the current icon theme declares `FollowsColorScheme=true`. The upstream Neuwaita index also inherits Adwaita and hicolor before Breeze, so missing KDE action icons can resolve to fixed-color black symbolic assets before KDE reaches recolorable Breeze icons. Reordering the real `Neuwaita` theme would leak Breeze's thinner symbolic icons into GTK apps such as Nautilus. KDE also uses names such as `folder-blue` for the default folder color, while upstream Neuwaita only ships the generic `folder` name. KDE's icon loader also treats spaces after commas in `Inherits=` literally in this setup, producing lookups such as `" hicolor"` and `" breeze"`.
**Status:** Workaround in place
**Resolution:** The `neuwaita` derivation in `home/gtk.nix` installs upstream-shaped `Neuwaita` for GTK after normalizing its inherited-theme list to comma-only separators, and a derived `Neuwaita-KDE` wrapper with `FollowsColorScheme=true` plus `Inherits=Neuwaita,breeze,Adwaita,hicolor`. Both installed themes get aliases for common folder names that upstream Neuwaita lacks, including `folder-blue`. The Qt target maps the shared `Neuwaita` state value to that wrapper for KDE only.

## OpenCode is better sourced from nixpkgs than from the upstream flake here
**Symptom:** Building OpenCode through the upstream `sst/opencode` flake on this repo used to pull in a large Deno/V8 toolchain closure and occasionally fail in the filtered Bun `node_modules` setup.
**Cause:** The upstream flake package is a source build, which brings in Deno plus `rusty_v8`, and its filtered Bun install path could still miss root-level packages such as `@tsconfig/bun`, `prettier`, or `glob` that some build steps expected.
**Status:** Workaround removed in favor of nixpkgs package
**Resolution:** `home/default.nix` now installs `pkgs.opencode` from the pinned `nixpkgs` set instead of overriding the upstream flake package. On the current `nixos-unstable` pin that package is already cacheable for `x86_64-linux`, so rebuilds fetch it directly from the binary cache and avoid the old source-build and fake-hash maintenance path entirely.

## Claude Code is better sourced from nixpkgs than from a repo-local npm pin here
**Symptom:** `nixos-rebuild` failed while building the repo-local `claude-code-2.1.91` overlay with `install: omitting directory ...-source` during `installPhase`.
**Cause:** The repo-local overlay pinned an older npm tarball and lockfile against a newer nixpkgs `claude-code` builder shape. Upstream nixpkgs has since moved on to a newer package revision and its maintained recipe no longer matches the local override's assumptions.
**Status:** Workaround removed in favor of nixpkgs package
**Resolution:** `system/configuration.nix` now drops the repo-local `overlays/claude-code.nix` override entirely and just uses `pkgs.claude-code` from the pinned `nixpkgs` set. On the current unstable pin that resolves to `claude-code-2.1.119`, which builds cleanly, so keeping a separate repo-local npm pin only adds maintenance risk without a compensating benefit.

## Haruna must match the session Qt/KDE stack
**Symptom:** A stable Haruna build can abort at startup, even with no media loaded, while the same file decodes cleanly in `ffplay`.
**Cause:** The Hyprland session exports `QT_QPA_PLATFORMTHEME=hyprqt6engine`, and the active `hyprqt6engine` plugin follows the unstable Qt/KDE stack. Pinning the whole Haruna package to stable makes it load a Qt platform theme plugin built against a different Qt/KDE ABI. Older unstable pins also risked local rebuilds through Haruna's `yt-dlp -> deno -> rusty_v8` dependency chain.
**Status:** Workaround in place
**Resolution:** `home/default.nix` now installs `pkgs.haruna` from the same pinned nixpkgs set as the rest of the Qt/KDE session, so it shares the session ABI with `hyprqt6engine`. Re-check the dry-run closure before reintroducing any stable Haruna pin; avoiding rebuild pressure is not worth mixing Qt/KDE plugin ABIs.

## OpenChamber source builds need a repo-pinned root manifest for npm
**Symptom:** A straight npm-based build of upstream `openchamber/openchamber` fails before dependency resolution finishes, typically with npm rejecting the root `overrides` versus direct dependency ranges or choking on the VS Code package's `workspace:*` dependency.
**Cause:** Upstream develops against Bun, and the full monorepo metadata currently assumes Bun's workspace/override behavior. The web workspace itself builds fine under npm once the root manifest is trimmed to the `packages/ui` and `packages/web` workspaces and the overridden CodeMirror versions are pinned exactly. Current upstream metadata also includes root-only tooling dependencies such as `sharp` for changelog-card generation that the packaged web runtime does not build.
**Status:** Workaround in place
**Resolution:** `pkgs/openchamber/cli.nix` source-builds OpenChamber from the upstream Git tag, but it replaces the root manifest with `pkgs/openchamber/package.json` and uses the generated `pkgs/openchamber/package-lock.json` so npm only sees the web-facing workspaces and their exact override pins. Keep root-only release tooling out of the trimmed manifest unless the web build starts using it. The v1.11.x web UI imports `@xenova/transformers`, so the Nix recipe also provides `vips` to satisfy the transitive `sharp` install without network downloads during `npm rebuild`.

## The Claude bridge only implements the OpenCode API subset OpenChamber currently needs
**Symptom:** Claude-backed chats work in both `claude-code` and `mixed` runtime modes for health checks, provider/model selection, session creation, session history, and basic streamed chat, but deeper OpenCode-only features such as true snapshot reverts, project sync history replay, or richer permission/question flows are still conservative stubs.
**Cause:** `pkgs/openchamber-claude-bridge/index.mjs` is intentionally a compatibility layer around the packaged `claude-code` CLI, not a full OpenCode reimplementation. `pkgs/openchamber-backend-mux/index.mjs` only multiplexes between real OpenCode and that bridge; it does not add missing OpenCode semantics to Claude-backed sessions.
**Status:** Intentional limitation
**Resolution:** Keep the bridge focused on the endpoint surface OpenChamber actively consumes. The local OpenChamber patches now add a `mixed` backend mode in addition to the single-backend OpenCode and Claude-only modes, and `pkgs/openchamber-backend-mux/index.mjs` binds each new chat to the backend implied by the selected model/provider at session creation time, forwards the selected `model` / `variant` / `agent` into that backend's `/session` create call, normalizes OpenCode's plain-string provider catalog entries before merging them with Claude Code, and serves merged `/experimental/session` pages so the provider settings UI and per-project sidebar can see both backends at once. Existing chats stay pinned to the backend they were created on. The wrappers pin both `opencode` and `claude-code`, so this path should not depend on ambient `PATH` for backend binaries.

## Mixed backend mode binds sessions at creation time
**Symptom:** In `mixed` mode, changing the selected model after a chat already exists does not migrate that chat from OpenCode to Claude Code, or vice versa.
**Cause:** `patches/openchamber/mixed-backend-mux.patch` changes OpenChamber so session creation carries the selected provider/model, and `pkgs/openchamber-backend-mux/index.mjs` records the resulting session ID to backend mapping. After that point, all session-specific routes are sent back to the original backend for that chat.
**Status:** Intentional design
**Resolution:** Treat backend choice as part of chat creation rather than a live per-message toggle. To move a conversation to the other backend, start a new chat while the desired provider/model is selected, then continue there or fork/copy the prompt into the new session.

## OpenChamber desktop launch state lives in `settings.json`
**Symptom:** `~/.config/openchamber/settings.json` now grows a `desktopLocalPort` key, the desktop launcher prefers reusing that port on the next launch, and repeated Vicinae launches refocus the existing app instead of spawning more local OpenChamber servers.
**Cause:** `pkgs/openchamber-desktop/src/main.rs` is a thin Tauri shell around the packaged `openchamber` CLI. It persists the last known desktop port in the shared OpenChamber settings file, falls back to port `57123` before picking a new ephemeral port, and rejects ports already claimed by the CLI runtime by probing `/api/system/info`. The Tauri app itself uses `tauri-plugin-single-instance`, so the duplicate-launch guard now lives at the desktop-process level instead of the old browser-launch wrapper, and the wrapper now fires `openchamber stop` asynchronously on exit so the window can close without waiting for the CLI's full shutdown path.
**Status:** Intentional design
**Resolution:** Treat `desktopLocalPort` as desktop runtime state owned by the Tauri wrapper. If the window closes and the background shutdown is still draining, a quick relaunch can temporarily reconnect to the still-running desktop runtime on that same port. If launches later get wedged on a stale port, stop the app and remove or edit that key; the next launch will retry the stored/default port sequence and can fall back to a fresh port when needed.

## OpenChamber desktop needs WebKit dmabuf disabled on current Wayland stacks
**Symptom:** Launching `openchamber-desktop` on the Hyprland/NVIDIA desktop can exit immediately with `Gdk-Message: Error 71 (Protocol error) dispatching to Wayland display`, often paired with `wp_linux_drm_syncobj_surface_v1 ... Missing acquire timeline`.
**Cause:** The current `webkitgtk_4_1` Wayland renderer path can negotiate the dmabuf/syncobj protocol combination incorrectly on this stack, which crashes the Tauri shell before the OpenChamber UI becomes usable.
**Status:** Workaround in place
**Resolution:** `pkgs/openchamber-desktop/default.nix` now wraps `openchamber-desktop` with `WEBKIT_DISABLE_DMABUF_RENDERER=1`, which keeps the app on a stable WebKit rendering path under Wayland without forcing the whole launcher onto X11.

## OpenChamber desktop popup interactions are sluggish on WebKitGTK without a lighter UI path
**Symptom:** In the local Tauri desktop shell, opening OpenChamber selects, dropdowns, and similar popup UI can feel delayed enough to make the whole app seem unresponsive, even when the backend endpoints themselves respond quickly.
**Cause:** The packaged desktop runtime is WebKitGTK rather than Chromium. The shared popup scroll chrome was doing more work than necessary at menu-open time by installing eager per-child resize observation in `packages/ui/src/components/ui/OverlayScrollbar.tsx` and by leaving mutation tracking enabled for the static option lists rendered by `packages/ui/src/components/ui/select.tsx`.
**Status:** Workaround in place
**Resolution:** `patches/openchamber/desktop-popup-performance.patch` now keeps the same UI behavior but reduces popup overhead by shrinking `OverlayScrollbar` observation to the scroll container itself and by disabling mutation observation for the static `Select` viewport content. Keep the patch local until upstream ships an equivalent WebKitGTK-oriented optimization.

## `tailscaled` can stall shutdown on physical hosts
**Symptom:** Reboot or poweroff can occasionally sit on "A stop job is running for Tailscale node agent" long enough to hit most of systemd's default 90 second stop timeout.
**Cause:** Upstream `tailscaled` shutdown is normally fast, but Linux `wgengine` teardown has had intermittent close/deadlock races. The current hosts use NetworkManager plus `resolvconf`/`openresolv`, so this repo does not rely on `systemd-resolved` staying up for Tailscale cleanup.
**Status:** Workaround in place
**Resolution:** `hosts/laptop/system.nix` and `hosts/desktop/system.nix` set `systemd.services.tailscaled.serviceConfig.TimeoutStopSec = "15s";`, which stays above observed normal stop times while bounding worst-case shutdown stalls.

## The laptop's `e-core-only` profile still keeps `cpu0` online
**Symptom:** Selecting the laptop's `e-core-only` power profile from Quickshell does not fully remove every P-core thread; one P-core thread remains online.
**Cause:** On this XPS 15 9520 kernel/runtime combination, `cpu0` has no `/sys/devices/system/cpu/cpu0/online` control, so Linux does not expose hot-unplug for the boot CPU even though the other P-core sibling threads are hotpluggable.
**Status:** Intentional limitation
**Resolution:** `hosts/laptop/system.nix` installs `laptop-power-profile`, which detects P-cores from `topology/thread_siblings_list`, re-enables all hotpluggable CPUs for the normal `performance` / `balanced` / `power-saver` modes, and offlines only the hotpluggable P-core threads for `e-core-only`. Treat that mode as an E-core-biased profile, not a literal "all P-cores gone" state.

## Helium tarballs need manual Qt wrapper handling
**Symptom:** The Helium package fails during the Qt pre-hook with "depends on qtbase, but no wrapping behavior was specified", or `autoPatchelfHook` complains about missing Qt5 SONAMEs from the bundled compatibility shim.
**Cause:** Upstream `helium-linux` releases currently ship both a Qt6 integration shim that the browser still uses and a dormant `libqt5_shim.so` that is no longer backed by runtime Qt5 libraries. The package also launches through the upstream `helium-wrapper` shell script, so it is not a normal `wrapQtAppsHook` target.
**Status:** Workaround in place
**Resolution:** `pkgs/helium/default.nix` uses `makeWrapper` for the launcher, sets `dontWrapQtApps = true`, and ignores the unused `libQt5Core.so.5`, `libQt5Gui.so.5`, and `libQt5Widgets.so.5` dependencies in `autoPatchelfIgnoreMissingDeps`.

## Helium uses a reverse-DNS user-data-dir
**Symptom:** Dropping External Extensions JSON files into `~/.config/helium/External Extensions/` (mirroring the path Chromium uses) silently does nothing — Helium never picks the extensions up.
**Cause:** Helium's user-data-dir on Linux is `~/.config/net.imput.helium/`, not `~/.config/helium/`. Home Manager's `programs.chromium` module has no Helium variant, so the path has to be wired by hand.
**Status:** Workaround in place
**Resolution:** `home/default.nix` defines `browserExtensions` as the shared extension-id list and feeds it both to `programs.chromium.extensions` and to `heliumExtensionFiles`, which generates `home.file."./.config/net.imput.helium/External Extensions/<id>.json"` entries with the same `external_update_url` payload Home Manager writes for Chromium.
