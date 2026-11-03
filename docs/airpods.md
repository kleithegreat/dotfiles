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
- Only a case within roughly arm's length raises the card, so a stranger's
  case across the room does not.
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

### The advert's address is not the pair's address
The case advertises from a rotating random LE address. A paired pair is matched
to it by product ID through BlueZ's `Modalias`, and an unpaired one is found
by name in BR/EDR discovery once its button is held.

### LibrePods' advert doc has the case battery in the wrong nibble
`Proximity Pairing Message.md` puts it in the high nibble; its own
`blemanager.cpp` reads the low nibble, and that is the version that works.
