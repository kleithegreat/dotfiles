# Nix Review

Reviewed on 2026-04-02.

## Verdict

The repo is structurally aligned with current NixOS and Home Manager guidance.
The remaining issues are mostly interface polish, not architectural defects.

## Strong Matches

| Area | Current state |
| --- | --- |
| Multi-host flake | One shared flake with explicit `nixosConfigurations.<host>` outputs |
| Home Manager integration | Embedded as a NixOS module with `useGlobalPkgs` and `useUserPackages` |
| Module arguments | `specialArgs` / `extraSpecialArgs` are used for repo-specific data rather than overloading reserved module arguments |
| Generated-file handling | Home Manager mostly deploys base config while the theming pipeline owns mutable outputs |

## Cleanup Candidates

| Severity | Finding | Why it matters |
| --- | --- | --- |
| Medium | `mkHost` expresses the target platform indirectly through an inline `nixpkgs.hostPlatform` module instead of an explicit `system = "x86_64-linux"` call site. | The platform is correct today, but less obvious than the common flake pattern. |
| Low | The `specialArgs` / `extraSpecialArgs` surface is broader than current modules need. | Passing both `inputs` and selected individual inputs widens the module API without much payoff. |
| Low | Host-specific Home Manager branching stays centralized in `home/default.nix`. | Fine at the current repo size, but it keeps host variance in one large shared file. |
| Low | The recursive Quickshell tree plus writable generated sibling file remains a deliberate special case. | It works today, but it is less mechanically obvious than the import-style base/generated split used elsewhere. |
| Low | `config/ghostty/config`, `config/starship/starship.toml`, `config/vicinae/settings.json`, and `config/vicinae/vicinae.json` are inert generated snapshots still committed under `config/`. | They are not the live Home Manager sources or theming bases, but they still make `config/` appear to own mutable generated outputs, which contradicts the spec and invites stale copies. |

Resolution for the snapshot divergence: remove those stale generated files rather
than broadening the `config/` contract. If any need to stay as examples or
fixtures, move them out of `config/` and label them accordingly.

Related low-level build and optimization caveats are tracked in
`docs/nix/QUIRKS.md`.
