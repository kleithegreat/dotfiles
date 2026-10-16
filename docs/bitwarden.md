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

### The desktop app registers Helium itself
It writes its own manifest and proxy copy into
`~/.config/net.imput.helium/NativeMessagingHosts/`, unlike Claude Code. A
symlink to the Chromium manifest there gets written through, repointing
Chromium at Helium's proxy.
