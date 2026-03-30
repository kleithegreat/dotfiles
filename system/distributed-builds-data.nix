{
  # Coordinator root keys allowed to authenticate to `nix-ssh` on the
  # NixOS build workers. Populate this with the public keys from:
  #   /root/.ssh/id_ed25519_nix_remote_build.pub
  # on the desktop and laptop.
  authorizedKeys = [ ];

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
    desktop = null;
    laptop = null;
    homelab = null;
  };

  # Public signing key for the homelab nix-serve cache.
  cachePublicKey = null;

  # Optional override if the cache should use a different hostname or port.
  cacheUrl = null;
}
