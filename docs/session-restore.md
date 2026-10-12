# Session Restore

## Intent

- Restoring a session means reopening apps and putting their windows back on
  their workspaces. It never means restoring what is inside a window: tabs,
  buffers and scrollback belong to the app. That is why this is a short list of
  known apps — the `APPS` table in `desktopctl/src/session.rs` — with what each
  one needs to come back, and not a generic "relaunch whatever was open".
- An app is either relaunched per window (a terminal: one process each, started
  on its workspace in its shell's working directory) or as a whole (browser,
  editor: launched once, and the windows it reopens by itself are then sorted
  onto workspaces by title). Adding an app is adding a row of one of those two
  kinds, never a third mechanism.
- Only the workspace is restored. Floating state, size, position and tiling
  order are not: every app on the list lives tiled, and each of those would be
  a second dispatcher per window for a state none of them is ever in.
- The daemon records and restores; nothing else writes the files under
  `$XDG_DATA_HOME/desktopctl/session/`. The running session is `recording.json`
  and the previous one is `last` in `state.json`. They are separate on purpose:
  the running session is recorded continuously, so the previous one has to live
  somewhere the recorder cannot reach or "on demand" would have nothing left to
  restore ten seconds after login.
- A recording becomes "the last session" when the daemon starts under a
  different Hyprland instance than the one that wrote it. A daemon restart
  inside one session must not rotate.
- Restoring consumes `last`. A second request — a double click, automatic
  restore followed by the power-menu row — must find nothing to duplicate.
- Automatic is the default. The mode is one flag in `state.json`; on demand
  means the same restore, asked for from the power menu instead of by
  `autostart.lua`.

## Quirks

### The recorder writes only what two consecutive looks agree on
A session going down closes its windows a moment before the daemon is told to
stop, and nothing on Hyprland's event socket tells "the user closed
everything" from "everything is being closed". Writing on change would
therefore replace a full session with an empty one in the last second of every
shutdown, and automatic restore would restore nothing. The ten-second
agreement in `daemon/session.rs` is that guard, not a debounce to tune down:
it has to stay longer than a session takes to die. The price is that the last
ten to twenty seconds before a crash are not recorded.

### A whole-app restore sorts after the fact, so windows land twice
Helium and VS Code reopen all their windows from one process, and Hyprland's
exec rules place only what that launch maps first. Their windows therefore
open on the active workspace and move once the window count has held still for
two seconds. Seeing them appear and then scatter is the mechanism working. A
browser that opens a single window is its own "continue where you left off"
setting being off, which nothing here can turn on.

Related: [[desktopctl]], [[hyprland]], [[quickshell]]
