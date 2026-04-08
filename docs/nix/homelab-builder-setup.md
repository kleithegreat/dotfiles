# Homelab Builder Setup

Target machine:

- Hostname: `homelab`
- Current IP: `192.168.8.153`
- OS: Ubuntu 25.10
- Nix: already installed in multi-user mode

This machine needs to do three jobs:

1. accept remote build traffic over SSH
2. store build outputs pushed from the desktop and laptop
3. serve those outputs over HTTP as a binary cache

## 1. Prerequisites

Make sure `openssh-server` is installed and enabled:

```bash
sudo apt install openssh-server
sudo systemctl enable --now ssh
```

Install `nix-serve` into the system profile so the systemd unit can use a stable path:

```bash
sudo nix profile install --profile /nix/var/nix/profiles/default nixpkgs#nix-serve
```

## 2. Create the dedicated SSH user

```bash
sudo adduser --system --group --home /var/lib/nix-ssh --shell /bin/bash nix-ssh
sudo install -d -o nix-ssh -g nix-ssh -m 700 /var/lib/nix-ssh/.ssh
sudo touch /var/lib/nix-ssh/.ssh/authorized_keys
sudo chown nix-ssh:nix-ssh /var/lib/nix-ssh/.ssh/authorized_keys
sudo chmod 600 /var/lib/nix-ssh/.ssh/authorized_keys
```

Append the desktop and laptop root builder public keys to `/var/lib/nix-ssh/.ssh/authorized_keys`.

Those are the keys printed by `./scripts/ensure-nix-builder-key.sh` on the NixOS machines.

## 3. Lock SSH down to the Nix daemon protocol

Create `/etc/ssh/sshd_config.d/nix-ssh.conf`:

```sshconfig
Match User nix-ssh
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  AllowAgentForwarding no
  AllowTcpForwarding no
  PermitTTY no
  PermitTunnel no
  X11Forwarding no
  ForceCommand /nix/var/nix/profiles/default/bin/nix-daemon --stdio
```

Then reload SSH:

```bash
sudo systemctl restart ssh
```

## 4. Allow the SSH user to talk to the Nix daemon

Edit `/etc/nix/nix.conf` and make sure these settings are present:

```ini
experimental-features = nix-command flakes
trusted-users = root nix-ssh
allowed-users = *
system-features = benchmark
substituters = https://cache.nixos.org https://hyprland.cachix.org https://vicinae.cachix.org
trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc= vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc=
```

Restart the daemon after editing:

```bash
sudo systemctl restart nix-daemon
```

`allowed-users` does not need to be narrowed for remote builds. The important setting is `trusted-users`, because the SSH account that Nix connects as must be trusted by the daemon.

## 5. Create the cache signing key

```bash
sudo install -d -m 0750 /etc/nix/cache
sudo nix-store --generate-binary-cache-key homelab-cache-1 /etc/nix/cache/cache-priv-key.pem /etc/nix/cache/cache-pub-key.pem
```

Keep `cache-priv-key.pem` only on the homelab. Copy the single-line contents of `cache-pub-key.pem` into `system/distributed-builds-data.nix` as `cachePublicKey`.

## 6. Run nix-serve under systemd

Create `/etc/systemd/system/nix-serve.service`:

```ini
[Unit]
Description=nix-serve binary cache
After=network.target nix-daemon.service
Wants=nix-daemon.service

[Service]
Environment=NIX_REMOTE=daemon
Environment=NIX_SECRET_KEY_FILE=/etc/nix/cache/cache-priv-key.pem
ExecStart=/nix/var/nix/profiles/default/bin/nix-serve --listen 0.0.0.0:5050
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Enable it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now nix-serve
```

## 7. Firewall

Remote builds and the cache do not require a separate Nix daemon TCP port. SSH on `22/tcp` carries the remote-store traffic, and the current repo expects `nix-serve` on `5050/tcp` (`system/distributed-builds-data.nix:30-31`).

If you use UFW, allow only the LAN:

```bash
sudo ufw allow from 192.168.8.0/24 to any port 22 proto tcp
sudo ufw allow from 192.168.8.0/24 to any port 5050 proto tcp
```

If you manage nftables directly, the equivalent rules are:

```nft
tcp dport 22 ip saddr 192.168.8.0/24 accept
tcp dport 5050 ip saddr 192.168.8.0/24 accept
```

## 8. Data to copy back into the repo

Host key for `nix.buildMachines.*.publicHostKey`:

```bash
sudo base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
```

Cache test:

```bash
curl http://192.168.8.153:5050/nix-cache-info
```

Once the desktop and laptop are rebuilt with the shared module, their post-build hook will push completed store paths to `ssh-ng://nix-ssh@homelab`, and `nix-serve` will immediately expose those paths to the rest of the LAN.
