# Tools Configuration Spec

## Scope

Ownership contract for tool configs managed through this repository. Covers the
split between repo-authored base files and pipeline-generated outputs, and the
criteria for when a tool gets its own `config/` subdirectory.

## Ownership Model

Every tool config managed by this repo falls into one of two ownership classes:

- **Base files** are repo-authored and checked into `config/<tool>/`. They are
  read-only to the theme pipeline — the pipeline may read them as input but
  never writes to them. Humans edit these files. Home Manager may symlink them
  into `~/.config/` or the pipeline may consume them during generation.

- **Generated outputs** are pipeline-owned and written to `~/.config/` (or
  another application-specific path) at theme-apply time. The pipeline may
  overwrite them on every theme change. Humans should not edit these files
  because edits will be silently replaced.

A base file and its generated output must never be the same path. The pipeline
reads from `config/<tool>/` and writes to `~/.config/<tool>/` (or the
application's settings path). This separation is enforced by the target modules
in `themes/lib/targets/`, where `BASE_PATH` and `OUTPUT_PATH` are always
distinct.

## Assembly Methods

Each theme target declares an assembly method that determines how the base file
and generated content relate:

| Method | Behavior | Base file role |
| --- | --- | --- |
| `concat` | Pipeline reads the base file, appends the generated block, and writes the combined result to the output path. | Structural skeleton — layout, keybindings, non-theming settings. Must not contain theming values. |
| `import` | Pipeline writes a standalone fragment to the output path. The base file contains an include/source directive that references the generated fragment. | Complete config that delegates theming to an external file via the application's native include mechanism. |
| `standalone` | Pipeline generates the entire output from scratch. No base file is read. | No base file. The target module contains all the logic. |
| `command` | Pipeline applies state through runtime commands (dconf, swww) with no persistent file output. | No base file. No output file. |

For `concat` and `import`, the base file lives at `config/<tool>/` and is the
repo-authored source of truth for that tool's non-theming behavior. For
`standalone` and `command`, the tool either has no repo config or its repo
config is deployed separately by Home Manager and only sources the generated
output.

## When a Tool Gets a `config/` Subdirectory

A tool warrants its own `config/<tool>/` subdirectory when **both** of these
are true:

1. The tool has runtime configuration that is authored by the user (not
   generated). This includes keybindings, editor options, layout settings,
   plugin declarations, and other behavioral config.

2. That configuration lives in a file format the tool reads directly from disk
   (TOML, JSON, INI, Lua, QML, etc.), as opposed to being expressed purely
   through Nix module options.

A tool should be configured purely in Nix (typically through Home Manager's
`programs.*` or `services.*` modules) when:

- The tool's entire useful configuration surface is covered by the Nix module
  (e.g., Zsh, fzf, zoxide, eza).
- The tool has no config file format of its own, or its config is trivially
  generated from Nix attributes.
- Adding a `config/` directory would just duplicate what the Nix module already
  expresses.

Tools that have **both** a Nix module for package management and a `config/`
directory for runtime behavior (e.g., Neovim, Starship) use Nix for the
package and `config/` for the runtime config. The Nix module should not
generate runtime config that conflicts with the repo-authored base.

## Snapshot Policy

Generated output files should not be committed to the repository. The canonical
outputs live at their `OUTPUT_PATH` locations and are recreated on every theme
apply.

Where historical snapshots exist in `config/` (e.g., `config/ghostty/config`,
`config/starship/starship.toml`, `config/vicinae/settings.json`), they are
stale artifacts. They are not read by any pipeline or deployment step. New
snapshots should not be added, and existing ones should be treated as
documentation of a past state rather than as active config.

Inert files that represent alternative or previous configurations (e.g.,
`config/vicinae/vicinae.json`) are similarly not consumed by any pipeline.
They should be removed when they no longer serve as useful reference.
