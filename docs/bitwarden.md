# Bitwarden

## Intent

- Biometric unlock is a polkit grant, not a PAM change. Bitwarden's "unlock
  with system authentication" raises a polkit prompt that hyprpolkitagent
  answers with fprintd, which is why the laptop only sets
  `polkit-1.fprintAuth`. Do not add PAM stanzas for Bitwarden — if the prompt
  stops working the fault is in the polkit agent or fprintd, not in PAM.
- The vault's own configuration — server URL, browser integration, biometric
  unlock, tray behavior — is app-internal state and stays that way. It is
  deliberately not declarative: none of it is reachable from Nix, and nothing
  in this repo should grow a module that pretends otherwise.

## Quirks

### Browser integration must be enabled in the desktop app before the extension can pair
The extension's "unlock with biometrics" toggle does nothing until the desktop
app has registered its native messaging host, and the failure is silent from
the extension's side. Enable Settings > App settings > "Allow browser
integration" in the desktop app first, then the extension toggle, then accept
the pairing prompt that the desktop app raises.

### "Browser integration not enabled" is usually a stale native messaging host
The desktop app writes
`~/.config/chromium/NativeMessagingHosts/com.8bit.bitwarden.json` pointing at a
`desktop_proxy` binary in the Nix store. That path is not updated when the
package is garbage-collected or upgraded, so the file can survive while the
binary it names is gone. Check the `path` field resolves before debugging
anything else.

### The window rule matches a class that upstream has changed before
`config/hypr/rules.lua` floats class `Bitwarden`. If the window stops floating
after an upgrade, read the real class out of `hyprctl clients` rather than
assuming the rule is wrong in some subtler way.
