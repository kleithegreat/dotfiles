# Homelab agent

## Intent

- The desktop is a k3s **agent** of the homelab cluster (the Homelab repo's
  `docs/moneymachine.md`), never a server: etcd quorum stays on the three
  homelab nodes, so the desktop can leave at any time.
- It joins only while moneymachine sweeps run. `k3s.service` is wanted by
  nothing; `systemctl start k3s` joins, `systemctl stop k3s` leaves, and the
  polkit rule lets `kevin` do both without sudo so the research agent can.
- Its taint `moneymachine/batch=true:NoSchedule` keeps homelab workloads off
  it; only moneymachine Jobs tolerate it.
- It joins over the wired LAN (`enp4s0`, a DHCP reservation for
  `192.168.8.131`), never over Wi-Fi or Tailscale: node traffic must reach the
  servers without NAT.
- The desktop's NFS exports are the Jobs' only data path:
  `/srv/moneymachine/inputs` read-only and `/srv/moneymachine/results`
  read-write, to the four cluster nodes only, every client squashed to
  `kevin`. Jobs never open SQLite over NFS: they copy in, work locally, and
  move finished files out atomically.
- The join token in `/etc/k3s/join-token` (root, `0600`) is a revocable
  bootstrap token from `k3s token create`, never the servers' own token.

## Quirks

### Tailscale's subnet route shadows the wired LAN
The Brume advertises `192.168.8.0/24`, and Tailscale's policy-routing table is
consulted before `main`, so with `--accept-routes` every packet to the homelab
goes through the tunnel and arrives SNATed as the Brume, which the nodes'
firewalls reject for VXLAN.

### node-exporter lands here anyway
The monitoring chart's DaemonSet tolerates every `NoSchedule` taint, so the
homelab's Prometheus scrapes the desktop while it is joined.
