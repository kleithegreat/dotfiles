# Nix

## Intent

- One flake, one explicit `nixosConfigurations.<host>` output per machine.
  `lib.systems.nixosHost` is shared plumbing only — module stack, `host` fact
  record, Home Manager embedding — and must not hide host policy, hardware
  choices, or package selection.
- Modules gate behavior on explicit host facts (`host.isPhysical`,
  `host.hyprland.*`), not by string-matching host names.
- Layer boundaries: `system/*.nix` owns shared privileged policy;
  `hosts/<name>/` owns hardware and host-only overrides; `home/*.nix` owns
  user packages, XDG deployment, and session glue; `config/` owns
  repo-authored application config that Home Manager deploys; `styling/` owns
  the theming data desktopctl deploys at apply time ([[theming]]); `lib/` owns
  helpers that are merged into `lib` and reachable everywhere. Installing a
  tool (Nix) and configuring it (`config/`) are separate responsibilities, and
  so are the two deployers: everything under `config/` reaches `~/.config` on
  rebuild, everything under `styling/` only on a theme apply. A file whose
  content desktopctl merges — the concat bases — belongs in `styling/bases`,
  never in `config/`, so the owner is legible from the path.
- Modules never receive packages or computed values as extra function
  arguments. What a module needs reaches it through `pkgs` (via an overlay),
  through `config`, or through a `specialArgs` entry that every module gets.
- `xdg.configFile` deploys base files and static trees only — never generated
  theme outputs, which must stay writable outside the store ([[theming]]).
  The recursive `quickshell/` and `nvim/` trees coexist with writable
  generated sibling files as a deliberate special case.
- GUI apps that need system D-Bus services or polkit actions must be installed
  through NixOS (`environment.systemPackages` or a NixOS module), not
  `home.packages` — user-profile packages never register system-scoped
  helpers. Current examples: partition-manager, bitwarden-desktop.
- Physical hosts run the stock nixpkgs kernel. A custom boot-critical kernel
  closure (Clang/LTO/CachyOS patches, forced initrd lists) already caused an
  undebuggable no-journal boot failure (desktop generation 73); keep runtime
  policy in `kernelParams`/sysctls/services and reintroduce Kconfig trims only
  as separately boot-validated changes.
- Intentional exceptions that audits keep flagging: `mitigations=off` on
  physical hosts (performance tradeoff), `max-jobs = 2` local build
  concurrency, and the checked-in `users.users.kevin.initialPassword` — a
  deliberate reproducible bootstrap login (SSH password auth stays disabled);
  don't remove it silently.

## Quirks — evaluation and build failures

### Narrow unfree/insecure predicates must cover transitive closures
`allowUnfreePredicate` must list not just chosen apps but names pulled in by
modules (`fonts.packages`, Steam, CUDA closures — `steam-unwrapped`, `sf-pro`,
`symbola`, the CUDA userspace set). Similarly, `bitwarden-desktop` and
`winboat` currently need exact-version EOL Electron insecure exceptions in
`system/configuration.nix`; drop each when nixpkgs moves them off EOL Electron
(`TODO.md`).

### Laptop Kconfig parent trims need child-symbol unsets
Disabling a parent subsystem (Nouveau, Hyper-V DRM, AMD SEV) makes nixpkgs'
mandatory child settings unreachable, and the kernel config builder errors
with `unused option`. Pair every parent trim in `hosts/laptop/system.nix` with
`lib.kernel.unset` for the orphaned children; do not reach for
`ignoreConfigErrors`, which hides real drift.

### Home Manager's release must track the evaluated nixpkgs release
When `nixos-unstable` advances to a new cycle before Home Manager cuts the
matching `release-*` branch, the old branch warns on every switch. The flake
tracks HM `master` (with `inputs.nixpkgs.follows`) until `release-26.11`
exists; move to the branch then, rather than disabling
`home.enableNixpkgsReleaseCheck`.

### `texlive.combined.scheme-medium` recurses on this pin
`scheme-medium` pulls `asymptote` through `collection-binextra` and evaluation
blows up. `home/packages.nix` builds `scheme-small` plus explicit extras.

### `cantarell-fonts` variable-OTF autohinting is broken on this pin
The default build fails in `otfautohint`. The overlay passes Meson flags
`-Dbuildvf=false -Dbuildstatics=true`; remove after a nixpkgs update proves
the default build works.

### Apple rotates `SF-Pro.dmg` behind a stable URL
The fixed-output hash eventually stops matching upstream bytes — refresh the
version date and `src.hash` in `pkgs/sf-pro/default.nix`. The current DMG's
`Payload~` is a plain cpio archive (no second gzip unpack); the derivation
tries `cpio` and falls back to `7z` for older layouts.

## Quirks — native optimizations

### The native overlay namespaces, it never shadows
Rewriting the global `pkgs` set gives every transitive consumer a new
derivation path and kills cache hits for packages that were never opted in.
`overlays/native-optimized.nix` therefore publishes `pkgs.optimized.<name>`
and leaves `pkgs.<name>` stock, which is also why it deliberately skips
`zstd`/`lz4` — optimizing low-level libraries pulls enormous rebuild cascades
through `libarchive`/`llvm`/`systemd`.

The trap the namespacing creates: a package resolves its dependencies from the
*unshadowed* set, so `wireplumber` and `quickshell` would each link stock
`pipewire` and drag a second copy of it into the closure. Cross-dependencies
inside `pkgs.optimized` are wired by hand with `.override`, and a new entry
that depends on another optimized package must be too.

### `pipe-operators` has to be bootstrapped by hand once
The config is written with `|>`, so evaluating it needs the feature that the
config itself turns on. A machine whose `/etc/nix/nix.conf` predates that
cannot evaluate its way to the rebuild that would install it. Break the loop
once, per machine:

    nrs --option experimental-features "nix-command flakes pipe-operators"

`nixos-rebuild` rejects `--extra-experimental-features` outright — it only
forwards `--option` — while a bare `nix eval` takes either. The flake's own
`nixConfig` block does not help: nix parses the file before reading it, and
ignores the whole block anyway until the user is in `trusted-users`.

### Native builds are fenced by per-host `requiredSystemFeatures`
`-march=native` output depends on the builder CPU, so identical flag strings
are not a safe cache boundary across hosts. Native derivations carry
`requiredSystemFeatures = [ "native-optimized-<host>" ]` and the host
advertises that feature in `nix.settings.system-features` *only while*
`pkgs.optimize.enabled` (`host.nativeOptimizations`) is on — unconditional
advertisement changes scheduling/cacheability even when the overlay is off.
Flake-input packages (Hyprland family, hyprqt6engine) go through
`pkgs.optimize.cc` from `lib/optimize.nix`, the same helper the overlay uses,
so they cannot diverge from the overlay policy. Bootstrap wrinkle: the switch that first enables the feature runs
through a daemon that doesn't advertise it yet, so the `nrs` wrapper passes
the target `system-features` to `sudo nixos-rebuild` directly (plain user
`--option system-features` is rejected as a restricted setting).

## Quirks — packages

### Neuwaita's upstream no longer exists — the vendored tarball is the only copy
The `RusticBard` GitHub account was deleted outright; the pinned rev is
unreachable from every remote, no fork carries it, Software Heritage never
archived it, and the fixed-output path is not on cache.nixos.org. The theme
was recovered from a surviving local build and vendored as
`pkgs/neuwaita/neuwaita-112525b2.tar.xz`. Treat that tarball as irreplaceable;
there is nowhere to re-fetch from. (KDE recoloring wrapper: see [[theming]].)

### AppImage apps need shell-parent launchers for Vicinae
Vicinae's detached launcher can treat an AppImage/FHS wrapper handoff as a
successful launch and lose the real app. The `pkgs/lmstudio` and
`pkgs/bambu-studio` packages wrap the upstream AppImages and rewrite their
desktop files to
absolute `$out/bin/<app>-desktop` launchers that invoke the binary *without*
`exec`, and normalize `StartupWMClass` to the class Hyprland actually reports.
After switching, refresh the long-lived Vicinae server (`nrs` does this via
`vicinae server --replace`) so it drops cached desktop entries. Bambu-specific:
stay on the stable Ubuntu AppImage (the nixpkgs source package is an untested
public beta; the Fedora AppImage links removed WebKitGTK 4.0), and if it opens
with locale errors, delete the stale `language` key from
`~/.config/BambuStudio/BambuStudio.conf`.

### Vicinae server has exactly one owner: Hyprland autostart
`home/packages.nix` installs `pkgs.vicinae` but leaves `services.vicinae`
disabled; `autostart.lua` starts the server. Re-enabling the HM service
creates a second competing server. The server caches desktop entries across
profile switches, hence the `--replace` refresh in `nrs`.

### Claude Code comes from a narrow `nixpkgs-claude` input
Model-support releases land in nixpkgs master before `nixos-unstable`
advances, so `flake.nix` carries a `nixpkgs-claude` input on master feeding
`overlays/claude-code.nix`. Keep it nixpkgs-sourced; a repo-local npm pin already
broke once against the moving upstream builder shape.

### Haruna must share the session Qt/KDE package set
`QT_QPA_PLATFORMTHEME=hyprqt6engine` loads a platform-theme plugin built
against the session's Qt/KDE ABI; pinning Haruna to a different nixpkgs makes
it load a mismatched plugin and abort at startup with no media loaded.

### Discord's Krisp module fails its signature check when Nix-packaged
`pkgs/discord-krisp/` carries a local backport of the nixpkgs patcher: it
patches the signature check, points `discord_voice` at the user-deployed
module, and repairs it at launch if Discord's updater overwrites it. Remove
once nixpkgs carries the fix upstream. After enabling, restart Discord and
re-enable noise suppression if the profile had forced `vadUseKrisp = false`.

### Helium is not a normal Qt/Chromium package
Upstream tarballs ship a dormant Qt5 shim with no runtime Qt5 (ignored via
`autoPatchelfIgnoreMissingDeps`), launch through their own wrapper script
(`dontWrapQtApps`, `makeWrapper`), and dlopen GTK file-chooser libraries that
never appear as `NEEDED` entries, so the launcher is prefixed with
GTK3/GTK4/media/GL paths by hand. Helium's user-data-dir is
`~/.config/net.imput.helium/`, not `~/.config/helium/` — External Extensions
JSON must be generated there (`heliumExtensionFiles` in `home/default.nix`
shares the ID list with `programs.chromium.extensions`).

### ComfyUI packaging traps
- PyTorch must come from the `-bin` wheels under `cudaPackages_13_3`
  (`pkgs/comfyui/python-packages.nix`): default nixpkgs torch with
  `cudaSupport` is an uncached hours-long source build, and `torch-bin` on the
  default CUDA 12 set is marked broken. The plain `torch`/`torchvision`/
  `torchaudio` attrs are aliased to the `-bin` packages so every downstream
  consumer shares one PyTorch. Do not silence the broken-package check
  instead. Related pins: `torchaudio-bin`'s `src` is repointed at upstream's
  cu130 wheel (nixpkgs pairs a cu130 torch with a cu128 torchaudio), and
  `torch-bin` gets `pythonRelaxDeps = [ "setuptools" ]` for its `<82` cap
  (guards only `torch.utils.cpp_extension`, unused here).
- The first build compiles NCCL and NVSHMEM from source for a long time —
  unavoidable link deps of the wheel, cached afterwards, per host.
- `--base-directory` neither seeds the tree nor covers the database:
  `comfyui.sh` creates the directory skeleton (generated in `installPhase`
  from the upstream tree) and passes an explicit `--database-url`.
- `comfyui-workflow-templates` is a metapackage over seven independently
  versioned sub-distributions; a partial install silently yields an empty
  template browser. Re-read its `requires_dist` on bumps.
- Custom nodes can't pip-install into the read-only store interpreter; declare
  extra deps via the `extraPythonPackages` override. Python is pinned to 3.13
  deliberately (upstream custom-node support), not drifting with `python3`.

## Quirks — services and runtime

### A `PathExists` unit must consume the file it triggers on
`PathExists` is level-triggered: the path unit re-arms the moment the service
exits and fires again while the file exists, spinning until the start limiter
fails both units — with the service itself exiting 0, which makes it look
healthy. The SDDM wallpaper sync consumes its staging file via
`trap 'rm -f ...' EXIT` (failure included, deliberately: desktopctl re-stages
on every theme apply). Any future `PathExists` unit needs the same discipline
or `PathChanged`.

### Stock `services.fstrim` would trim the Windows NVMe
The stock unit trims every mounted filesystem, including the shared EFI
partition mounted from the Windows drive. `system/services.nix` replaces it
with `fstrim-root.service`/`.timer` pinned to `/`.

### Chromium-family file pickers use the GTK portal
`xdg.portal.config` exposes only the Hyprland and GTK backends with GTK as
FileChooser, and `home/xdg.nix` writes the same user-level `portals.conf` so a
stale HM symlink can't force the brittle KDE backend back (which broke
first-login file pickers). Session-side env-import ordering matters too — see
[[hyprland]].

### `nrs` mutes Hyprland's config watcher during activation
Home Manager swaps `~/.config/hypr/` symlinks one at a time and Hyprland's
watcher treats each swap as a config change, reloading mid-activation against
momentarily missing `require`d files. `nrs` sets `misc:disable_autoreload`
for the rebuild and restores the prior value via `trap ... EXIT INT TERM` —
EXIT alone does not run when SIGINT kills zsh, which would strand autoreload
off for the session. It skips the guard (and the Vicinae refresh) when
Hyprland is unreachable so it still works from a TTY/SSH.

### MGLRU `min_ttl_ms` is the working-set protection, not `vm.*` sysctls
`system/physical-host.nix` applies thrash protection through
`systemd.services.mglru-tuning` writing `/sys/kernel/mm/lru_gen/min_ttl_ms`.
Don't go looking for LE9-style `vm.anon_min_kbytes` knobs, and don't add
low-swappiness values: swap is zram-only, where the kernel default of 60 is
the right policy — the desktop deliberately keeps only the writeback sysctls.

### Only the laptop resolves its timezone from location
`automatic-timezoned` runs on the laptop alone; the desktop pins
`time.timeZone` because a stationary host gains nothing from geolocation and
loses correctness when GeoClue guesses wrong. On the laptop the daemon only
acts when GeoClue returns coordinates, so after travel check `where-am-i`
under the user session and `journalctl -u geoclue.service` before debugging
the timezone service. Locale and keymap are static on purpose everywhere.

### `tailscaled` can stall shutdown
Intermittent wgengine teardown races can eat most of systemd's 90s stop
timeout. Physical hosts cap `TimeoutStopSec=15s` on tailscaled.

### The laptop's `e-core-only` profile keeps one P-core thread online
`cpu0` exposes no `online` control on the XPS 15 9520, so the
`laptop-power-profile` helper can only offline the hotpluggable P-core
threads — treat the mode as E-core-*biased*. Detection details that matter:
P-core threads are identified by having more than one entry in
`thread_siblings_list` (the kernel reports both ranges like `0-1` and lists
like `0,6`, which broke comma-counting), and efficiency mode is detected by
any `cpu*/online` reading `0`, because an offlined CPU loses its whole
`topology/` sysfs group. Real-hardware validation is still pending
(`TODO.md`).

The helper lives in `desktopctl/src/bin/laptop-power-profile/` and is a
second binary of the `desktopctl` crate rather than a subcommand: the polkit
rule in `hosts/laptop/system.nix` grants passwordless pkexec by matching the
program path, so a subcommand would extend that grant to all of `desktopctl`.
`hosts/laptop/system.nix` symlinks just that binary into `systemPackages`;
the package wraps it with `powerprofilesctl` on `PATH`, because pkexec resets
the environment.

Because `desktopctl` is installed on every host, the helper refuses to run
unless the CPU is actually hybrid — some SMT threads and some without. On a
uniform-SMT machine "offline every P-core thread" means the whole processor,
so the topology check, not the packaging, is the safeguard. It exits non-zero
there, which is what makes the Quickshell backend probe fall through.

### Generic `SF Pro` looks soft without fontconfig tuning
Fontconfig could pick the variable catch-all face over the `SF Pro Text`
optical cut and defaulted to grayscale AA. The shared config sets
`subpixel.rgba = "rgb"` and prepends `SF Pro Text` for generic `SF Pro`
requests; if a monitor fringes, set the panel's real subpixel order.

### Nautilus thumbnails need explicit helper packages
`glib` (for `gsettings`) and `gdk-pixbuf` (thumbnailer + metadata) must be in
`home.packages` alongside `nautilus`; after adding them, `nautilus -q` and
clear `~/.cache/thumbnails/fail/`.

### Hyprland's Cachix is intentionally not configured
The compositor/plugin stack is locally patched and native-built, so its store
paths can't exist in the public cache; the substituter only added noisy
negative lookups. Re-add only if the stack returns to unpatched upstream.

Related: [[hyprland]], [[nvidia]], [[theming]], [[tools]], [[grub]]
