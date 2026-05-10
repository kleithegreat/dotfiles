# Nix Review

Reviewed on 2026-04-19.

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
| Low | The recursive Quickshell tree plus writable generated sibling file remains a deliberate special case. | It works today and no longer requires a committed generated snapshot, but it is less mechanically obvious than the import-style base/generated split used elsewhere. |

Related low-level build and optimization caveats are tracked in
`docs/nix/QUIRKS.md`.

The retained Ableton Live 12 Lite investigation is documented separately in
`docs/nix/ableton-live.md` as historical, not actively pursued work.
