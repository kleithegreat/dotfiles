# Bitwarden Desktop + Chromium Biometric Unlock

Runbook for the Bitwarden desktop app, browser integration, and
fingerprint-backed biometric unlock.

## Current Wiring

- **Install**: `pkgs.bitwarden-desktop` is in `environment.systemPackages` in
  `system/services.nix` (not Home Manager). The nixpkgs package ships a polkit
  policy at `share/polkit-1/actions/com.bitwarden.Bitwarden.policy`, and only
  system-level packages get polkit policies linked into the system-wide
  actions directory (see nixpkgs#344073 and the "Home Manager packages do not
  register system-scoped helpers" quirk in `docs/nix/QUIRKS.md`). The package
  also includes the `desktop_proxy` native messaging binary required for
  browser integration. The package currently needs the narrow
  `electron-39.8.10` insecure-package exception in `system/configuration.nix`.
- **No autostart**: Bitwarden is not launched at session start. The old
  `exec-once = bitwarden` line was removed from `config/hypr/autostart.conf`;
  launch it manually or from the launcher. An owner question about restoring
  autostart is pending.
- **Window rule**: `config/hypr/rules.conf` keeps
  `windowrule = match:class Bitwarden, float on, center on`.
- **Fingerprint path**: `hosts/laptop/system.nix` sets
  `polkit-1.fprintAuth = true`, so Bitwarden's "Unlock with system
  authentication" polkit prompt is presented by hyprpolkitagent with fprintd.
  No PAM changes required.

## Manual Setup

1. Enroll fingerprints if needed: `fprintd-list $USER`, then `fprintd-enroll`
   (and `fprintd-enroll -f left-index-finger`).
2. Open Bitwarden manually and log in. For a self-hosted Vaultwarden server,
   set the server URL via the gear icon on the login screen first.
3. Enable tray behavior in Settings: "Close to tray icon", "Start to tray
   icon" (if present), "Minimize to tray icon".
4. Enable browser integration: Settings > App settings > "Allow browser
   integration". This registers the `desktop_proxy` native messaging host at
   `~/.config/chromium/NativeMessagingHosts/`.
5. Enable biometric unlock: Settings > Security > "Unlock with system
   authentication" (triggers the polkit/fingerprint prompt).
6. In the Chromium extension: Settings > Account security > "Unlock with
   biometrics", then accept the connection prompt in the desktop app.
7. Verify: lock the extension (or restart Chromium), open the extension popup,
   touch the fingerprint reader — the vault should unlock.

## Troubleshooting

- **Extension says "browser integration not enabled"**: Check that
  `~/.config/chromium/NativeMessagingHosts/com.8bit.bitwarden.json` exists and
  its `path` field points at a valid `desktop_proxy` binary in the Nix store.
- **Fingerprint prompt doesn't appear**: Verify `fprintd-verify` works
  standalone and hyprpolkitagent is running (`pgrep hyprpolkitagent`).
- **Window rule doesn't match**: Run `hyprctl clients` with Bitwarden open and
  update the class in `config/hypr/rules.conf` if it differs from `Bitwarden`.
- **No tray icon**: The Quickshell bar needs its system tray
  (StatusNotifierItem) widget for the icon to appear.

The Bitwarden CLI (`bw`) is intentionally not installed; only the desktop app
and its `desktop_proxy` are needed for browser integration.
