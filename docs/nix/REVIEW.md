# Nix Review

Reviewed on 2026-04-08.

## Verdict

The repo is structurally aligned with current NixOS and Home Manager guidance.
The remaining issues are mostly interface polish, not architectural defects.

## Strong Matches

| Area | Current state |
| --- | --- |
| Multi-host flake | One shared flake with explicit `nixosConfigurations.<host>` outputs |
| Home Manager integration | Embedded as a NixOS module with `useGlobalPkgs` and `useUserPackages` |
| Module arguments | `specialArgs` / `extraSpecialArgs` are used for repo-specific data rather than overloading reserved module arguments, and the Home Manager side now passes only the values consumed under `home/` |
| Generated-file handling | Home Manager mostly deploys base config while the theming pipeline owns mutable outputs |

## Cleanup Candidates

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Low | Host-specific Home Manager branching stays centralized in `home/default.nix`. | Fine at the current repo size, but it keeps host variance in one large shared file. |
| Low | The recursive Quickshell tree plus writable generated sibling file remains a deliberate special case. | It works today, but it is less mechanically obvious than the import-style base/generated split used elsewhere. |
| Medium | Ableton Live 12 Lite is still not in a reproducibly working state despite the current Wine/PipeWire plumbing. | The host wiring is largely correct, but the remaining GUI/input bug and the ongoing Wine-NSPA source-port effort mean the repo does not yet meet the original "launches, draws correctly, and is usable" goal. |

Related low-level build and optimization caveats are tracked in
`docs/nix/QUIRKS.md`.
