# Nix Specification

This spec defines how the flake is partitioned between shared system config,
host overlays, Home Manager, and repo-managed user config. It is the intent
document; see `docs/nix/ARCHITECTURE.md` for the current implementation map.

## Repository Contract

| Concern | Contract |
| --- | --- |
| Flake shape | One flake, with one explicit `nixosConfigurations.<host>` output per machine. |
| Host inventory | Hosts are added at the flake output layer, not by creating extra flakes or repo roots. |
| `mkHost` role | Shared plumbing only: common module stack, shared arguments, Home Manager embedding, and repo-wide toggles. |
| `mkHost` non-role | It must not hide host policy, hardware choices, package selection, or user config. |
| Host facts | `mkHost` passes a structured `host` record through the module args. Modules may use `host.name` for identity, but behavior gates should read explicit fact fields such as `host.isPhysical` or `host.hyprland.*` instead of string-matching host names. |

## Layer Boundaries

| Layer | Owns | Must not own |
| --- | --- | --- |
| `system/configuration.nix` and `system/*.nix` | Shared privileged policy, shared services, desktop packaging, system packages, `/etc`-style config, and shared physical-host boot/runtime defaults | Machine-specific hardware or host-only overrides |
| `hosts/<name>/system.nix` | Hardware, filesystems, GPU layout, host-only services/packages, privileged per-host overrides, and boot policy that differs from the shared physical-host baseline | Shared system defaults |
| `home/default.nix` and `home/*.nix` | User packages, XDG config deployment, desktop entries, MIME defaults, user scripts, session hooks | Root-owned boot or service policy |
| `config/` | Version-controlled application config that Home Manager deploys into the home directory | Mutable generated outputs |

## Placement Rules

- Put a change in the shared system layer when it is privileged and expected on
  every host, or on every host in a shared hardware class already modeled in
  shared config.
- Put it in a host module when it is privileged and tied to one machine or
  hardware class.
- Put it in Home Manager when it produces user-home state or user-session
  behavior.
- User-facing desktop apps that also need system D-Bus service or polkit action
  registration still belong in the NixOS layer that owns that privileged
  registration; Home Manager alone is not sufficient for those helpers.
- Put it under `config/` when it is the repo-authored base file that Home
  Manager should deploy.
- Keep host-specific user config under `hosts/<name>/` only when the file
  itself materially differs by host.

## `xdg.configFile` Policy

| Allowed | Forbidden |
| --- | --- |
| Base files that import generated fragments | Final generated outputs |
| Static recursively deployed trees such as `quickshell/` and `nvim/` | Runtime state files written by the theming pipeline |
| Static packaged assets | Any output that must stay writable after activation |

Constraints:

- Home Manager owns version-controlled base config; it does not own mutable
  theme outputs.
- Generated theme outputs must remain writable outside the Nix store.
- Recursive Home Manager trees may coexist with generated sibling files when
  the runtime output is not itself store-managed.
- The only current committed generated-snapshot exception is
  `config/quickshell/GeneratedTheme.json`, which ships inside the recursive
  Quickshell tree and is then overwritten in place by `desktopctl theme sync`
  and later runtime theme applies.
- Outside that documented Quickshell exception, generated snapshots accidentally
  committed under `config/` are still forbidden outputs even if no current
  module deploys them; remove or relocate them instead of treating them as
  owned base config.

## Packages Versus Repo Config

| Concern | Owner |
| --- | --- |
| Package availability, pinning, overrides, module integration | Nix |
| Runtime behavior of installed tools | Repo config under `config/` |
| Generated palette/font/theme fragments | The theming pipeline |

Invariants:

- Installing a tool and configuring a tool are separate responsibilities.
- Base config may reference generated fragments, but generated fragments must
  not become the home of unrelated non-theming behavior.
- If a concern is primarily about services, packages, or module arguments, it
  belongs in Nix. If it is primarily about application behavior, it belongs in
  repo-managed config.
