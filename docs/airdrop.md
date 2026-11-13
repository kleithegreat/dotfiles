# AirDrop

## Intent

- Owly owns the radio (owlyd) and the protocol (owly-airdrop). desktopctl
  owns the AirDrop session between them, and the shell only presents it
  ([[desktopctl]], [[quickshell]]). owly-airdrop is built from the flake's own
  `owly` input, so `flake.lock` is owly's one pin and the library never drifts
  from the owlyd that runs.
- Receiving is "Everyone for 10 Minutes" only, as an iPhone offers it.
  "Contacts Only" needs Apple-signed contact records. Visibility always ends by
  itself.
- An offer always asks. Nothing is accepted unasked, and a received link is
  shown, never opened, until you open it. Files land in Downloads.
- The radio is held only while visible or sharing. Where Owly runs exclusive,
  Wi-Fi is down for exactly that long, and the shell says so before you turn
  it on.
- Sharing starts from a context menu, as on a Mac: Nautilus's and Helium's
  (the extension in `desktopctl/browser/`), or Super+Shift+A for the selection
  anywhere. Text that is one link goes as that link, anything else as a note
  that lives only as long as the share. A share turns Bluetooth on for the
  advert that wakes iPhones, and back off if it was off.

## Quirks

### An empty receiver list for the first seconds is normal
An iPhone's mDNS does not reach `awdl0`, so receivers are also found by
`/Discover` at each AWDL peer, and a phone only opens its port once the BLE
advert has woken it. Upstream measured about 15 s.

### Plain `cargo` needs `nix develop` first
desktopctl reaches owly-airdrop through `desktopctl/.owly`, a gitignored link
to the owly input that the dev shell creates, and Nix creates for the build.
After `nix flake update owly`, the Nix build fails on a stale `Cargo.lock` if
owly-airdrop's dependencies moved; `cargo update` inside `nix develop` fixes it.

### The user service needs no polkit rule
owlyd asks polkit before lending the radio, and desktopctl runs outside the
login session's scope, so it looks like it needs a rule. It does not: polkit
judges it by the user's active display session (`pkcheck` passes).
