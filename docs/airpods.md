# AirPods

## Intent

- `desktopctl` owns everything AirPods-specific: the AAP channel to a
  connected pair and the BLE monitor that sees an open case. The shell only
  presents what it publishes ([[desktopctl]], [[quickshell]]). LibrePods is not
  used: it is an app with its own window and tray, and nothing can read its
  state.
- The daemon never pairs, connects or trusts a device. That is BlueZ device
  state, and its one write path is Quickshell's Bluetooth service.
- The card follows the iPhone's flow. Opening a case raises it, closing the
  lid takes away the status and connect cards, and a setup in progress survives
  the lid. The only step that differs is the one iOS also shows for AirPods
  not on your Apple account: hold the setup button. Pairing without the button
  needs Apple account keys and is impossible here.
- An advert cannot say whose case it is (that part is encrypted to the
  owner's Apple account), and a paired pair is matched by model, so distance
  is the only thing between you and a stranger's case. By default only a
  case next to the computer raises the card, as an iPhone asks of a case it
  does not know; Settings → Bluetooth widens it to arm's length or turns it
  off.
- Taking a pod out pauses whatever is playing; putting it back resumes only
  what that pause stopped.

## Quirks

### No card at all means bluetoothd is not running experimental
`AdvertisementMonitorManager1` is only exported with `Experimental = true`
(`system/physical-host.nix`), and a switch does not restart bluetoothd to pick
it up: `systemctl restart bluetooth`. Without it the daemon logs "no proximity
monitor" and everything else (the AAP channel, Control Center, Settings) still
works, so the card is the only symptom. The Bluetooth adapter is also off at
boot; no card appears until it is on.

### Pairing that lasts until the first disconnect is an adapter that will not bond
BlueZ leaves the adapter non-bondable while no pairing agent is registered,
and nothing here registers one. The shell's pair then completes for the
session only: audio plays, `Paired` stays false, the device vanishes from
BlueZ on disconnect, and every reconnect fails with "Authentication Failed"
because the AirPods kept their key. `AlwaysPairable` in
`system/physical-host.nix` is what makes it bond.

### `Failed to Add Adv Patterns Monitor with status 0x0a` is a stale kernel add
An add that fails while the adapter is off (status `0x03`) leaves its pending
command behind in `__add_adv_patterns_monitor`, and every later add from anyone
is Busy until the adapter powers off. Restarting desktopctl does not clear it,
and `RegisterMonitor` still succeeds, so only bluetoothd's journal shows it.
The laptop carries `bluetooth-mgmt-failed-monitor-add-leaves-no-pending.patch`;
on the desktop's stock kernel, power-cycle the adapter. Delete the patch once
upstream removes the pending command on that error path.

### The advert's address is not the pair's address
The case advertises from a rotating random LE address. A paired pair is matched
to it by product ID through BlueZ's `Modalias`, and an unpaired one is found
by name in BR/EDR discovery once its button is held.

### LibrePods' advert doc has the case battery in the wrong nibble
`Proximity Pairing Message.md` puts it in the high nibble; its own
`blemanager.cpp` reads the low nibble, and that is the version that works.
