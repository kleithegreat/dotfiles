# Bitwarden

## Intent

- Biometric unlock is a polkit grant answered by hyprpolkitagent with fprintd
  (`polkit-1.fprintAuth`), not a PAM change. Don't add PAM stanzas; a broken
  prompt is the agent or fprintd.
- The vault's own configuration is app-internal state and stays undeclared.

## Quirks

### Browser integration must be enabled in the desktop app first
The extension's biometrics toggle fails silently until the desktop app's
"Allow browser integration" registers its native messaging host.

### "Browser integration not enabled" is usually a stale native messaging host
`~/.config/chromium/NativeMessagingHosts/com.8bit.bitwarden.json` names a
store `desktop_proxy` that GC or an upgrade can remove; check its `path` first.
