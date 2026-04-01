# Nix Review

## Scope

This review compares the current repository against:

- the NixOS wiki guidance for flakes and `nixos-rebuild`
- the Nixpkgs module-system documentation for `specialArgs`
- the Home Manager manual and NixOS-module options
- `THEMING.md` section 4 and the later Home Manager migration notes

The goal here is to document where the current setup matches common documented practice, where it diverges, and whether each divergence looks intentional or accidental.

## Overall Assessment

The setup is broadly in line with current documented NixOS and Home Manager patterns:

- one flake exposing `nixosConfigurations`
- one shared system module plus one host module per machine
- Home Manager embedded as a NixOS module
- `home-manager.useGlobalPkgs = true`
- `home-manager.useUserPackages = true`

The main divergences are not fundamental architecture problems. Most are one of:

- a deliberate simplification for a single-user, three-host repo
- a broader-than-necessary `specialArgs` surface
- stale repo documentation around theming
- one mildly unconventional `nixosSystem` detail

## What Matches Current Guidance

### Multi-host flake structure

The published examples on the NixOS wiki and in Home Manager use a flake with `nixosConfigurations.<hostname> = nixpkgs.lib.nixosSystem { ... };` and then compose shared modules plus host-specific modules. This repo does the same in substance.

The local `mkHost` wrapper does not change that model. It just centralizes the repeated module stack.

Assessment: aligned.

### Home Manager as a NixOS module

The current integration:

- imports `home-manager.nixosModules.home-manager`
- sets `home-manager.useGlobalPkgs = true`
- sets `home-manager.useUserPackages = true`
- assigns `home-manager.users.kevin = import ./home;`

That is the same shape as the Home Manager flake example. The Home Manager options documentation also explicitly describes `useGlobalPkgs`, `useUserPackages`, and `extraSpecialArgs`.

`useGlobalPkgs = true` is especially consistent with current guidance because the manual notes that it avoids a second nixpkgs evaluation and keeps Home Manager consistent with the system package set.

Assessment: aligned.

### `specialArgs` as the place for flake-provided module arguments

The Nixpkgs module-system docs describe `specialArgs` as application-specific module arguments that are available while evaluating imports. The NixOS wiki FAQ also shows passing flake inputs through `specialArgs` so modules can consume pinned inputs directly.

This repo uses that mechanism correctly:

- system modules get `hostName`, `march`, feature toggles, and flake inputs
- Home Manager modules get `dotfilesPath`, `hostName`, and selected flake inputs

The repo does not misuse `specialArgs.lib`, which the Nixpkgs manual explicitly warns against.

Assessment: aligned.

### Generated-file handling for most Home Manager config

`THEMING.md` section 4 says generated files must not be managed by Home Manager because `xdg.configFile` produces read-only store symlinks.

The current Home Manager config mostly follows that rule.

Correct current patterns include:

- `alacritty.toml` is a base file that imports generated `theme.toml`
- `tmux.conf` is a base file that sources generated `colors.conf`
- `zathurarc` is a base file that includes generated `colors`
- `hypr/appearance.conf` is a base file that sources generated `appearance-theme.conf`
- `snappy-switcher/themes` is symlinked, while generated runtime config is left writable
- there is no Home Manager symlink for the generated Ghostty config
- there is no Home Manager symlink for the generated Starship config
- there is no Home Manager symlink for the final Vicinae config

Assessment: aligned.

## Intentional Divergences

### `mkHost` is a local convenience wrapper, not a published pattern

The upstream docs usually show each `nixosConfigurations.<name>` entry written out directly. They do not prescribe a `mkHost` abstraction, but they also do not discourage one.

In this repo, `mkHost` is a reasonable de-duplication layer because all three hosts share the same:

- system base module
- Home Manager integration
- feature-flag plumbing
- `specialArgs` wiring

Nothing in the repo suggests that `mkHost` is hiding materially different per-host logic. With three hosts, it remains understandable.

Assessment: intentional and reasonable.

### Host-specific Home Manager files are selected with `hostName` conditionals

The Home Manager manual’s FAQ for multiple users and machines describes a common pattern of one top-level file per unique user/machine combination, plus shared modules.

This repo instead keeps a single `home/default.nix` and branches on `hostName` for a small number of Hyprland files:

- monitors
- input devices
- environment

That is a divergence from the manual’s “typical” pattern, but for a single-user repo with three hosts it looks deliberate. The current branching surface is still small.

The tradeoff is that host conditionals accumulate inside the shared Home Manager entry point instead of being pushed out to host-specific entry modules.

Assessment: intentional simplification.

### Host hardware is inlined in `hosts/*/system.nix`

The NixOS wiki examples still center the generated `hardware-configuration.nix` pattern and modular imports from `configuration.nix`.

This repo does not keep a separate autogenerated hardware file. Instead, the host modules inline the hardware and filesystem declarations that would normally live there.

That is not contrary to NixOS module semantics; it just chooses a different file boundary. The comments in the host modules explicitly note that the hardware section came from `nixos-generate-config`, so this appears deliberate.

Assessment: intentional simplification.

### Quickshell relies on recursive Home Manager symlinks plus a runtime-generated sibling file

`home/default.nix` still manages `xdg.configFile."quickshell"` recursively, while the theme pipeline writes `~/.config/quickshell/GeneratedTheme.json` at runtime.

`THEMING.md` explicitly called this out as an approach to verify, and the current repo has clearly adopted it.

There is no evidence in the current tree that this is failing. The architecture assumes:

- Home Manager manages the QML source files
- `GeneratedTheme.json` coexists alongside those symlinked files

Assessment: intentional, with a documented assumption rather than a fully independent upstream recommendation.

## Divergences That Look More Accidental Or Stale

### `nixosSystem` does not set `system = "x86_64-linux"` explicitly

Current NixOS wiki and Home Manager flake examples set `system` directly in the `nixosSystem` call.

This repo does not. Instead, `mkHost` injects:

```nix
{ nixpkgs.hostPlatform = "x86_64-linux"; }
```

as an inline module.

That still expresses the target platform, but it is more indirect than the documented examples and makes the evaluation platform less obvious at the call site.

Because the helper already exists and all three hosts are x86_64 Linux machines, this is easy to miss and does not look like a deliberate architectural statement. It looks more like an unconventional implementation detail.

Assessment: likely accidental or at least under-documented.

### `specialArgs` and `extraSpecialArgs` expose more than current modules use

The repo’s use of `specialArgs` is valid, but the surface area is broader than necessary.

Current examples:

- system modules receive both `hyprland` and `inputs.hyprland`
- system modules receive a broad `inputs` attrset even though only part of it is used
- Home Manager receives `hyprland`, `hyprland-plugins`, and `hyprqt6engine`, but `home/default.nix` only uses `vicinae`, `snappy-switcher`, `dotfilesPath`, and `hostName`

This is not wrong. Passing all flake inputs under one namespace is a common convenience pattern. The extra breadth becomes a review point because the repo is doing both:

- a broad namespace (`inputs`)
- some individually passed inputs

That widens the module API without a clear need.

Assessment: likely convenience-driven drift rather than an intentional interface design.

### `THEMING.md` no longer exactly matches the live Home Manager setup

This is the clearest stale-doc divergence in the repo.

`THEMING.md` still says or implies:

- the Home Manager activation hook should run `apply-theme all`
- Hyprland plugin config lives at `pluginsettings.conf`

The live code now does this instead:

- `home.activation.applyTheme` runs `themes/apply-theme sync`
- Hyprland sources `plugins.conf`

The difference matters because `sync` is not just a renamed `all`:

- it disables runtime reload commands
- it skips targets marked `SYNC_SAFE = false`

The current code therefore implements a stricter rebuild-time synchronization path than the design doc describes.

Assessment: accidental documentation drift.

## Module Organization Review

The current module organization is coherent:

- `system/configuration.nix` is the shared OS baseline
- `hosts/*/system.nix` are true host overlays
- `home/default.nix` is the shared user baseline
- `home/*.nix` split out distinct user concerns

That said, two organization choices are worth noting against common documented patterns:

1. Home Manager host selection is centralized in `home/default.nix` instead of using host-specific top-level Home Manager entry files.
2. Hardware config is inlined into host modules instead of being imported from generated hardware files.

Neither is inherently wrong. Both reduce file count. Both also shift more responsibility into a few central files.

Assessment: organized and readable today, but optimized for a small repo rather than for maximal conventionality.

## `xdg.configFile` Review

Against `THEMING.md` section 4, the current `xdg.configFile` usage is mostly disciplined.

### Good current usage

These are base files or non-generated assets and are appropriate to keep under Home Manager:

- `hypr/hyprland.conf`
- `hypr/appearance.conf`
- `hypr/autostart.conf`
- `hypr/input.conf`
- `hypr/input-devices.conf`
- `hypr/keybinds.conf`
- `hypr/rules.conf`
- `hypr/hypridle.conf`
- `hypr/hyprlock.conf`
- `hypr/plugins.conf`
- `quickshell/`
- `nvim/`
- `alacritty/alacritty.toml`
- `tmux/tmux.conf`
- `zathura/zathurarc`
- `git/ignore`
- packaged Snappy Switcher themes

These files either:

- are not generated at all, or
- are base files that import generated fragments

### No evident generated-file violations remain

The repo does not currently symlink the generated final outputs that `THEMING.md` warned about, such as:

- final Ghostty config
- final Starship config
- final Vicinae config
- generated Hyprland color/theme fragments

That is the right direction.

### Remaining caveat

The one caveat is Quickshell. The repo is intentionally relying on the recursive-symlink layout to coexist with a runtime-generated sibling file. That is consistent with the repo’s own design notes, but it is still more assumption-heavy than the simpler “base file imports generated file” pattern used by Alacritty, tmux, Zathura, and Hyprland.

Assessment: mostly aligned, with one deliberate special case.

## `specialArgs` Surface Review

From the upstream docs, the important standard is not “never use `specialArgs`”. It is:

- use it for application-specific values
- avoid hijacking reserved arguments like `lib`
- keep the module API understandable

Against that standard:

- the current usage is legitimate
- the current surface is broader than necessary

Reasonable current uses:

- `hostName`
- `march`
- `enableMarchOptimizations`
- `enableDistributedBuilds`
- `dotfilesPath`
- `inputs` as a single namespace for pinned flake dependencies

Broader-than-needed current exposure:

- passing both `hyprland` and `inputs.hyprland`
- passing Home Manager inputs that are not consumed by current home modules

Assessment: correct mechanism, slightly overexposed interface.

## Home Manager Integration Review

The Home Manager integration follows current recommended patterns closely.

Positive points:

- embedded as a NixOS module rather than managed separately
- `useGlobalPkgs = true`
- `useUserPackages = true`
- `backupFileExtension = "bak"`
- one imported Home Manager root module with smaller imported submodules
- `programs.home-manager.enable = true`

The only real review note is that host-specific Home Manager behavior is handled by `hostName` branching inside the shared root module instead of by separate top-level host/user Home Manager entry files.

Assessment: aligned overall.

## Bottom Line

The current setup is structurally sound and largely consistent with current wiki/manual guidance.

The main cleanup opportunities are:

- make the `nixosSystem` platform explicit at the call site
- trim unused `specialArgs` / `extraSpecialArgs`
- update `THEMING.md` so it matches `plugins.conf` and `apply-theme sync`

Everything else reads as a conscious tradeoff toward a compact single-user, multi-host flake rather than as a design mistake.

## References

- NixOS Wiki: NixOS system configuration
  https://wiki.nixos.org/wiki/NixOS_system_configuration
- NixOS Wiki: nixos-rebuild
  https://wiki.nixos.org/wiki/Nixos-rebuild
- NixOS Wiki: FAQ
  https://wiki.nixos.org/wiki/FAQ
- Nixpkgs Reference Manual: module system / `specialArgs`
  https://nixos.org/manual/nixpkgs/unstable/
- Nix Reference Manual: `nix flake`
  https://releases.nixos.org/nix/nix-2.32.1/manual/command-ref/new-cli/nix3-flake.html
- Home Manager home page
  https://home-manager.dev/
- Home Manager manual
  https://home-manager.dev/manual/23.05/
- Home Manager NixOS module options
  https://home-manager.dev/manual/23.05/nixos-options.html
