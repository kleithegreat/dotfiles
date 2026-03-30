#!/usr/bin/env bash
set -euo pipefail

key_path=/root/.ssh/id_ed25519_nix_remote_build
host_key_path=/etc/ssh/ssh_host_ed25519_key.pub
comment="nix-remote-build@$(hostname -s)"

sudo install -d -m 700 /root/.ssh

if ! sudo test -f "$key_path"; then
  sudo ssh-keygen -t ed25519 -N "" -f "$key_path" -C "$comment"
fi

printf 'Builder public key (%s.pub):\n' "$key_path"
sudo cat "${key_path}.pub"
printf '\n'

if sudo test -f "$host_key_path"; then
  printf 'Base64 SSH host key (%s):\n' "$host_key_path"
  sudo base64 -w0 "$host_key_path"
  printf '\n'
fi
