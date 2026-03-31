{
  # Coordinator root keys allowed to authenticate to `nix-ssh` on the
  # NixOS build workers. Populate this with the public keys from:
  #   /root/.ssh/id_ed25519_nix_remote_build.pub
  # on the desktop and laptop.
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJzgQTPYL5dnnqhhX+hBsthM9DmVKol7rIDxx6WEGGxv nix-remote-build@desktop"
  ];

  # Use DHCP reservations or stable local DNS names before relying on these
  # long-term. The current homelab address matches the present LAN lease.
  connectHosts = {
    desktop = "desktop.local";
    laptop = "laptop.local";
    homelab = "192.168.8.153";
  };

  # Optional base64-encoded host keys for nix.buildMachines.*.publicHostKey.
  # Generate with:
  #   base64 -w0 /etc/ssh/ssh_host_ed25519_key.pub
  publicHostKeys = {
    desktop = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSU00R0kvNE1OMUNlZ1o1Q2c4UkszT0lQMy9wZ012TFdoL0tzZXBQVXlhRlUgcm9vdEBkZXNrdG9wCg==";
    laptop = null;
    homelab = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUVWaW9KYngyaWNNS3lteXRwWkhDUG51aDZLeGYvaXg0TVhIcjhpZ052a1Qgcm9vdEBob21lbGFiCg==";
  };

  # Public signing key for the homelab nix-serve cache.
  cachePublicKey = "homelab-cache-1:OvwiHTm1eYgYgqLEcT3OIzKbuHS1UiNnzOUZPRJ4ljc=";

  # Optional override if the cache should use a different hostname or port.
  cacheUrl = "http://192.168.8.153:5050";
}
