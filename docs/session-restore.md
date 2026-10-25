# Session Restore

## Intent

- Restoring means reopening a short list of known apps (`APPS` in
  `desktopctl/src/session.rs`) and putting their windows back on their
  workspaces, with what is inside a window where it can be brought back. Each
  app relaunches either per window (a terminal, in its shell's cwd, resuming
  the Claude Code session it was running) or as a whole (browser, editor,
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

### Recording halts on logind's announcement, not on a final look
Shutdown closes windows before the daemon is stopped, and Helium and Code
close theirs on `PrepareForShutdown` itself, so a look taken on the
announcement or on SIGTERM already records a dying session. The recorder keeps
the last look from before it; the `shutdown` delay lock (`desktopctl` in
`systemd-inhibit --list`) is what guarantees the halt lands before anything is
killed. Without the lock, or with the watch task failed, closed windows come
back after a reboot.

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
