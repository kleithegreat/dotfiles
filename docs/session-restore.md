# Session Restore

## Intent

- Restoring means reopening apps and putting their windows back on their
  workspaces — never what is inside a window. Hence a short list of known
  apps (`APPS` in `desktopctl/src/session.rs`), each relaunched either per
  window (a terminal, in its shell's cwd) or as a whole (browser, editor,
  whose reopened windows are sorted by title). A new app is a row of one of
  those two kinds, never a third mechanism.
- Only the workspace is restored: every listed app lives tiled.
- The daemon alone writes `$XDG_DATA_HOME/desktopctl/session/`. The running
  session (`recording.json`) and the previous one (`last` in `state.json`) are
  separate so continuous recording can't overwrite what on-demand restore
  needs. A recording becomes `last` only when the daemon starts under a
  different Hyprland instance.
- Restoring consumes `last`, so a second request finds nothing to duplicate.
- Automatic is the default; on demand is the same restore, asked for from the
  power menu.

## Quirks

### The recorder writes only what two consecutive looks agree on
Shutdown closes windows before the daemon stops, and nothing distinguishes
that from the user closing everything. The ten-second agreement in
`daemon/session.rs` must outlast a dying session; it is not a debounce to
tune. The price: the last 10–20s before a crash go unrecorded.

### A whole-app restore parks its windows before it can place them
A named window rule sends the app's new windows to `special:restoring` until
every saved window is back (or the count holds for two seconds), then they are
moved and the rule switched off. Windows that never appear are still parked
(`hyprctl clients`). The daemon clears these rules at start, since a stuck one
swallows every later window. A browser restoring one window has its own
"continue where you left off" off.

### A browser that went down with the session believes it crashed
Chromium leaves `exit_type: Crashed` after a reboot and opens one blank window
with a restore bubble. Helium's `prepare` step rewrites the flag; a new
`Whole` app that restores after a quit but not a reboot needs the same.
