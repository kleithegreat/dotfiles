# Nix Architecture

## Scope

This document describes the current NixOS and Home Manager architecture in this repository as of April 1, 2026. It is based on:

- `flake.nix`
- `flake.lock` for input inventory
- `system/configuration.nix`
- `system/distributed-builds.nix`
- `overlays/march-optimized.nix`
- `hosts/laptop/system.nix`
- `hosts/desktop/system.nix`
- `hosts/vm/system.nix`
- every file under `home/`

## Flake Shape

The flake exposes one output family: `nixosConfigurations`.

- `nixosConfigurations.vm`
- `nixosConfigurations.laptop`
- `nixosConfigurations.desktop`

All three are built through a small helper, `mkHost`, in `flake.nix`. That helper accepts:

- `hostName`
- `march`
- `hostModule`

`mkHost` then calls `nixpkgs.lib.nixosSystem` with a fixed module stack:

1. an inline module setting `nixpkgs.hostPlatform = "x86_64-linux"`
2. `./system/configuration.nix`
3. the selected host module under `./hosts/*/system.nix`
4. `home-manager.nixosModules.home-manager`
5. an inline Home Manager configuration block

This makes the repository a single-flake, multi-host setup with one shared system layer, one host-specific system layer per machine, and one embedded Home Manager layer for user configuration.

The flake also defines two repo-level feature toggles:

- `enableMarchOptimizations`
- `enableDistributedBuilds`

These are not NixOS options. They are ordinary Nix values in `flake.nix`, so changing them requires editing the flake and rebuilding.

## Direct Inputs

The direct inputs declared in `flake.nix` are:

| Input | Purpose in this repo |
| --- | --- |
| `nixpkgs` | Base package set and `lib.nixosSystem` |
| `home-manager` | NixOS-module integration for the user environment |
| `hyprland` | Upstream Hyprland packages used as the base for the compositor and portal |
| `hyprland-plugins` | Plugin packages rebuilt against the pinned Hyprland package |
| `hyprqt6engine` | Qt platform theme engine used for Hyprland-native Qt theming |
| `vicinae` | Home Manager module plus package/cache integration for the launcher |
| `snappy-switcher` | Package and bundled themes for the Alt-Tab switcher |

Input follow relationships are used to keep key package sets aligned:

- `home-manager.inputs.nixpkgs.follows = "nixpkgs"`
- `hyprland-plugins.inputs.hyprland.follows = "hyprland"`
- `hyprqt6engine.inputs.nixpkgs.follows = "nixpkgs"`

That keeps Home Manager and Hyprland-adjacent packages on the same pinned nixpkgs / Hyprland revisions as the rest of the system.

## Lockfile Inventory

`flake.lock` adds the transitive inventory that comes with those direct inputs. The notable groups are:

- Hyprland stack: `aquamarine`, `hyprcursor`, `hyprgraphics`, `hyprland-guiutils`, `hyprland-protocols`, `hyprlang`, `hyprutils`, `hyprwayland-scanner`, `hyprwire`, `xdph`
- Generic flake plumbing: `flake-utils`, `flake-compat`, `systems`
- Dependency helpers pulled in by upstream flakes: `gitignore`, `pre-commit-hooks`

This repo does not reference those transitive flakes directly in `flake.nix`; they are locked because upstream inputs depend on them.

## `mkHost`

`mkHost` is the central abstraction in the flake. Its job is not to define behavior by itself; it just keeps the host declarations short and ensures that every host gets the same baseline module stack and argument wiring.

Today it standardizes:

- the shared system module
- the host module slot
- Home Manager integration
- the `specialArgs` surface passed into NixOS modules
- the `extraSpecialArgs` surface passed into Home Manager modules

The arguments exposed to NixOS modules are:

- `hyprland`
- `hostName`
- `march`
- `enableMarchOptimizations`
- `enableDistributedBuilds`
- `inputs`

The arguments exposed to Home Manager modules are:

- `dotfilesPath`
- `hostName`
- `hyprland`
- `hyprland-plugins`
- `hyprqt6engine`
- `vicinae`
- `snappy-switcher`

`dotfilesPath = self` gives Home Manager modules a stable reference to the flake source tree, which is then used for `xdg.configFile` and `home.file` sources.

## System Layer Split

### Shared System Configuration

`system/configuration.nix` is the common NixOS base for every host. It owns:

- shared Nix settings, caches, GC, and registry entries
- common users and groups
- common desktop services
- common firewall, PKI, audio, Bluetooth, printing, Samba, Docker, libvirt, geoclue, Tailscale, and Mullvad settings
- the shared package baseline in `environment.systemPackages`
- Hyprland packaging, patching, and portal wiring
- the `distributed-builds.nix` import

This file also constructs several package-level customizations before the module body:

- `optimizedPackages` from `overlays/march-optimized.nix`
- a locally overridden `hyprqt6engine`
- a patched `Hyprland`
- a patched `xdg-desktop-portal-hyprland`
- patched `hyprbars` and `hyprexpo`
- a `HYPR_PLUGIN_DIR` symlink tree
- a customized SDDM theme package

### Host-Specific System Configuration

Each host module owns the machine-specific layer:

| Host | Module | Main responsibilities |
| --- | --- | --- |
| `vm` | `hosts/vm/system.nix` | QEMU guest profile, EFI/systemd-boot, VM disk layout |
| `laptop` | `hosts/laptop/system.nix` | EFI+GRUB, hybrid Intel/NVIDIA setup, power/fingerprint/captive portal, laptop service overrides |
| `desktop` | `hosts/desktop/system.nix` | EFI+GRUB, dedicated NVIDIA setup, Steam, desktop-only EGL override, extra storage mount |

The host modules carry the hardware and machine-specific policy that would otherwise clutter the shared system module:

- filesystems
- swap
- bootloader choices
- kernel modules
- GPU layout
- per-host service overrides
- host-only packages

## Home Manager Split

### Shared Home Manager Entry Point

`home/default.nix` is the single Home Manager entry point imported by:

- `home-manager.users.kevin = import ./home;`

It owns:

- `home.username`, `home.homeDirectory`, and `home.stateVersion`
- the main user package set
- most `xdg.configFile` mappings
- `home.file` scripts under `~/.local/bin`
- MIME defaults and desktop entry overrides
- Chromium extensions
- theme activation

It also imports smaller Home Manager modules:

- `home/shell.nix`
- `home/gtk.nix`
- `home/sun-schedule.nix`
- `vicinae.homeManagerModules.default`

### Host-Specific Home Manager Data

Home Manager host-specific behavior is handled inside `home/default.nix` by branching on `hostName`.

That branching selects host-specific files for:

- `hypr/input-devices.conf`
- `hypr/monitors.conf`
- `hypr/env.conf`

For `vm`, the module falls back to inline `text` for the Hyprland files that do not have dedicated host-specific sources.

### Home Manager Submodules

The imported `home/*` modules have clear boundaries:

- `home/shell.nix`: Zsh, shell tools, Git, session variables, aliases, and prompt/navigation tooling
- `home/gtk.nix`: GTK theme packages plus small dconf settings
- `home/sun-schedule.nix`: a user systemd timer and service for the sunrise/sunset scheduler

## Generated Versus Version-Controlled User Config

The repo uses Home Manager for version-controlled base config and a separate theming pipeline for generated config.

The important split is:

- base config stays symlinked from the repo through `xdg.configFile`
- generated theme outputs are written at activation time or runtime and are not managed as store symlinks

Examples of the base-file pattern:

- `config/alacritty/alacritty.toml` imports `~/.config/alacritty/theme.toml`
- `config/tmux/tmux.conf` sources `~/.config/tmux/colors.conf`
- `config/zathura/zathurarc` includes `colors`
- `config/hypr/appearance.conf` sources `~/.config/hypr/appearance-theme.conf`

This lets Home Manager own the stable entry files while `themes/apply-theme` owns the writable generated fragments.

## Rebuild Workflow

The current rebuild path is:

1. edit the repo
2. run `sudo nixos-rebuild switch --flake ~/repos/dotfiles#<host>`
3. activate the new system generation
4. let the embedded Home Manager activation run

In practice, the preferred shortcut is the Zsh alias in `home/shell.nix`:

```sh
nrs
```

That alias temporarily disables Hyprland autoreload, runs:

```sh
sudo nixos-rebuild switch --flake ~/repos/dotfiles#${hostName}
```

and then re-enables autoreload.

Per current `nixos-rebuild` flake behavior, the build target is:

```sh
nixosConfigurations.<host>.config.system.build.toplevel
```

and only tracked Git files are copied into the flake source in the store. New files therefore need to be staged before they are visible to the build.

### What Happens During Activation

Because Home Manager is embedded as a NixOS module, the home environment is rebuilt as part of the same system switch.

After Home Manager writes its managed files, `home.activation.applyTheme` runs:

```sh
${dotfilesPath}/themes/apply-theme sync
```

This is important:

- the repo currently uses `sync`, not `all`
- `sync` writes theme-managed config without live-session reload commands
- `sync` also skips targets marked `SYNC_SAFE = false`

At the moment that means activation writes the theme-managed files that are safe for rebuild-time synchronization, while runtime-only targets such as GTK stateful updates and wallpaper actions are not forced during activation.

## Optional Performance And Build Features

Two repo-level toggles change the architecture when enabled.

### `enableMarchOptimizations`

When true, `overlays/march-optimized.nix` adds host-specific compiler flags and system features to a curated package set. The current host values are:

- `desktop`: `rocketlake`
- `laptop`: `alderlake`
- `vm`: `null`

This is used both for ordinary nixpkgs packages and for the flake-provided Hyprland package tree.

### `enableDistributedBuilds`

When true, `system/distributed-builds.nix` enables:

- `nix.distributedBuilds`
- `nix.buildMachines`
- `nix.sshServe`
- a post-build hook that copies outputs to the homelab cache
- extra firewall rules for LAN builder access

This only activates on `desktop` and `laptop`.

## References

- NixOS Wiki: NixOS system configuration
  https://wiki.nixos.org/wiki/NixOS_system_configuration
- NixOS Wiki: nixos-rebuild
  https://wiki.nixos.org/wiki/Nixos-rebuild
- NixOS Wiki: FAQ
  https://wiki.nixos.org/wiki/FAQ
- Nix Reference Manual: `nix flake`
  https://releases.nixos.org/nix/nix-2.32.1/manual/command-ref/new-cli/nix3-flake.html
- Nixpkgs Reference Manual: module system / `specialArgs`
  https://nixos.org/manual/nixpkgs/unstable/
- Home Manager home page
  https://home-manager.dev/
- Home Manager manual
  https://home-manager.dev/manual/23.05/
- Home Manager NixOS module options
  https://home-manager.dev/manual/23.05/nixos-options.html
