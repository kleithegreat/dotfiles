# Bitwarden

## Intent

- Biometric unlock is a polkit grant answered by hyprpolkitagent with howdy,
  then fprintd (the laptop's `polkit-1` stack), not a Bitwarden-specific PAM
  change. Don't add PAM stanzas; a broken prompt is the agent, howdy or fprintd.
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
