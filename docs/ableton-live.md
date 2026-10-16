# Ableton Live

## Intent

- Live runs on `ableton-wine` from the `shibco/ableton-linux` flake input, not
  on nixpkgs Wine. Stock Wine 11 (stable and staging) and wine-tkg 11.6 all
  land clicks progressively below the cursor: the child window's
  `WM_NCCALCSIZE` top inset grows with Live's menu band, and every later stage
  (Vulkan surface, `screen_to_client()`) faithfully consumes that bad rect.
  Their patches fix it. Do not swap the runtime without re-testing a
  piano-roll divider drag and a note-edge resize near the bottom of the window.
- The prefix (`~/.wine-ableton`) and the Live install inside it are mutable
  state owned by upstream's `setup-prefix`; the repo provides only the runtime
  and `ntsync`. The launcher rewrites the prefix's DPI registry values on every
  start, so they must not be pinned declaratively.
- Audio is PipeASIO talking to PipeWire directly. No JACK layer, no WineASIO.

## Quirks

- There is no binary cache and the input follows our `nixpkgs`, so any nixpkgs
  bump rebuilds Wine from source (~10 minutes on the laptop). A rebuild sitting
  in `wine-d2d1-nspa` is compiling, not hung.
- `setup-prefix` copies some runtime DLLs (`comdlg32.so`, the PipeASIO halves)
  into the prefix. After bumping the input, rerun
  `$(dirname $(readlink -f $(which ableton-live)))/../share/ableton-wine/scripts/setup-prefix.sh --refresh`,
  or the prefix keeps the old copies and the new runtime looks broken.
- The `.desktop` files in `~/.local/share/applications` named `ableton-live`
  and `io.github.shibco.ableton-linux.*` are written by `setup-prefix` and
  shadow the package's same-named entries. They launch through
  `~/.local/share/ableton-wine/runtime`, a link the launcher re-points at each
  start and which doubles as a GC root. Neither is stray state.
