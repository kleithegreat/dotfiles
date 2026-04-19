# Distributed Builds

The shared NixOS logic lives in `system/distributed-builds.nix`.
Environment-specific values live in `system/distributed-builds-data.nix`.

## Current state

- The subsystem exists in the shared module graph, but the
  `enableDistributedBuilds` binding in `flake.nix` currently stays `false`.
- When that flag is flipped on, the `enableDistributedBuilds'` host gate in
  `system/distributed-builds.nix` enables the distributed-build path only on
  `desktop` and `laptop`.
- The module still uses `ssh-ng` with a dedicated `nix-ssh` account on the
  NixOS workers and pushes completed outputs to the homelab over SSH.
- The `cacheUrl` fallback in `system/distributed-builds.nix` uses `:5000`, but
  the repo's live data file overrides the cache URL to
  `http://192.168.8.153:5050` through `cacheUrl` in
  `system/distributed-builds-data.nix`.

## What the setup does when enabled

- Enables `nix.distributedBuilds` on desktop and laptop only
- Uses `ssh-ng` with a dedicated `nix-ssh` account on the NixOS workers
- Pushes completed build outputs to the homelab over SSH so `nix-serve` can
  publish them
- Adds a local cache substituter pointing at the homelab cache URL from
  `system/distributed-builds-data.nix`
- Restricts the NixOS SSH builder port to `192.168.8.0/24`
- Tags native-optimized derivations with
  `requiredSystemFeatures = [ "native-optimized-<host>" ]`

That last point is deliberate. With `-march=native` and `target-cpu=native`,
desktop and laptop can produce different machine code even when the literal flag
strings are identical, so the native-optimized derivations must stay pinned to
their owning host. Generic `x86_64-linux` work remains shareable; the
host-native rebuilds do not.

## One-time data to collect

1. On `desktop` and `laptop`, run:

   ```bash
   ./scripts/ensure-nix-builder-key.sh
   ```

   This creates `/root/.ssh/id_ed25519_nix_remote_build` if it does not exist,
   prints the root builder public key, and prints the machine's base64-encoded
   SSH host key.

2. On the homelab, follow `docs/nix/homelab-builder-setup.md`, then collect:

   - the base64-encoded SSH host key
   - the `homelab-cache-1:...` public cache signing key

3. Update `system/distributed-builds-data.nix`:

   - put the desktop and laptop root builder public keys into `authorizedKeys`
   - put the desktop, laptop, and homelab base64 host keys into
     `publicHostKeys`
   - put the homelab cache signing key into `cachePublicKey`
   - set `cacheUrl` to the actual cache endpoint; the current repo expects
     `http://192.168.8.153:5050`

## Deploy order

1. Set up the homelab first.
2. Flip `enableDistributedBuilds` to `true`.
3. Rebuild `desktop`.
4. Rebuild `laptop`.

## Smoke tests

From each NixOS machine, test the remote stores explicitly:

```bash
sudo nix store info --store 'ssh-ng://nix-ssh@laptop.local?ssh-key=/root/.ssh/id_ed25519_nix_remote_build'
sudo nix store info --store 'ssh-ng://nix-ssh@desktop.local?ssh-key=/root/.ssh/id_ed25519_nix_remote_build'
sudo nix store info --store 'ssh-ng://nix-ssh@192.168.8.153?ssh-key=/root/.ssh/id_ed25519_nix_remote_build'
curl http://192.168.8.153:5050/nix-cache-info
```

After that, `nixos-rebuild` and `nix build` should start scheduling generic
`x86_64-linux` work across the other two builders while leaving
`native-optimized-<host>` derivations on their owning machine.
