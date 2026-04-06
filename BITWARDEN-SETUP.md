# Bitwarden Desktop + Chromium Biometric Unlock Setup

## Changes Made

### 1. Installed bitwarden-desktop (`home/default.nix`)
Added `bitwarden-desktop` to home-manager packages. The nixpkgs package is built
from the upstream AppImage (not Snap/Flatpak), so it includes the `desktop_proxy`
native messaging binary required for browser integration.

### 2. Auto-start on Hyprland login (`config/hypr/autostart.conf`)
Added `exec-once = bitwarden`. The app will open a window on first launch until
you enable "Close to tray" / "Start to tray" in its settings (see manual steps).

### 3. Window rule (`config/hypr/rules.conf`)
Added `float on, center on` for class `Bitwarden`. If the class doesn't match
after installation, run `hyprctl clients` while the window is open and adjust the
class in the rule.

### 4. Polkit / fingerprint path (no changes needed)
The existing config in `hosts/laptop/system.nix` already sets
`polkit-1.fprintAuth = true`. When Bitwarden's "Unlock with system
authentication" triggers a polkit prompt, hyprpolkitagent will present the
fingerprint dialog via fprintd. No PAM changes required.

## Manual Steps After Rebuild

### First-time setup

1. **Rebuild**: `sudo nixos-rebuild switch --flake .`

2. **Enroll fingerprints** (if not already enrolled):
   ```
   fprintd-list $USER          # check existing enrollments
   fprintd-enroll              # enroll right index finger
   fprintd-enroll -f left-index-finger
   ```

3. **Log in to Bitwarden desktop**:
   - Open Bitwarden (it will launch automatically on next Hyprland session)
   - If you use a self-hosted Vaultwarden server: click the gear icon on the
     login screen, set the server URL before logging in
   - Log in with your master password

4. **Enable tray behavior** (so it doesn't open a window on every login):
   - File > Settings (or gear icon)
   - Enable **"Close to tray icon"**
   - Enable **"Start to tray icon"** (if available in your version)
   - Enable **"Minimize to tray icon"**

5. **Enable browser integration** in the desktop app:
   - File > Settings > App settings
   - Enable **"Allow browser integration"**
   - The app will register the `desktop_proxy` native messaging host with
     Chromium at `~/.config/chromium/NativeMessagingHosts/`

6. **Enable biometric unlock** in the desktop app:
   - File > Settings > Security
   - Enable **"Unlock with system authentication"** (triggers polkit/fingerprint)
   - You'll be prompted to authenticate to confirm

### Chromium extension setup

7. **Connect the Chromium extension to the desktop app**:
   - Open the Bitwarden extension popup in Chromium
   - Go to Settings > Account security (or Settings > Options in older versions)
   - Enable **"Unlock with biometrics"**
   - The extension will prompt you to allow the connection in the desktop app
   - Accept the prompt in the desktop app

### Verification

8. **Test the flow**:
   - Lock the Bitwarden extension (or restart Chromium)
   - Click the extension popup — it should show a fingerprint/biometric prompt
   - Touch the fingerprint reader — the vault should unlock

### Troubleshooting

- **Extension says "browser integration not enabled"**: Verify the native
  messaging host manifest exists at
  `~/.config/chromium/NativeMessagingHosts/com.8bit.bitwarden.json` and that its
  `path` field points to a valid `desktop_proxy` binary in the Nix store.

- **Fingerprint prompt doesn't appear**: Verify `fprintd-verify` works
  standalone, and that hyprpolkitagent is running (`hyprctl clients` or
  `pgrep hyprpolkitagent`).

- **Window rule doesn't match**: Run `hyprctl clients | grep -i class` with
  Bitwarden open, and update the class in `config/hypr/rules.conf` if it differs
  from `Bitwarden`.

- **No tray icon**: Your Quickshell config may need a system tray widget
  (StatusNotifierItem/SNI support) for the tray icon to appear.

## Not installed

- **Bitwarden CLI (`bw`)**: Not required for browser integration. Only the
  desktop app and its `desktop_proxy` are needed.
