# Homelab

## Intent

- The desktop is not a node of the homelab cluster. Its one role there is the
  NFS export `/srv/moneymachine/mirror`, where the cluster's live recorders and
  ledgers are copied (the Homelab repo's `docs/moneymachine.md`): read-write,
  to the three homelab nodes only, every client squashed to `kevin`. It is the
  recordings' only copy.
- The nodes reach it over the wired LAN (`enp4s0`, a DHCP reservation for
  `192.168.8.131`), never over Wi-Fi or Tailscale: the export admits the nodes'
  own addresses, so their traffic must arrive without NAT.

## Quirks

### Tailscale's subnet route shadows the wired LAN
The Brume advertises `192.168.8.0/24`, and Tailscale's policy-routing table is
consulted before `main`, so with `--accept-routes` every packet to the homelab
goes through the tunnel and arrives SNATed as the Brume, which the export
rejects.
