# Distributed Builds

The shared NixOS logic lives in `system/distributed-builds.nix`. Environment-specific values live in `system/distributed-builds-data.nix`.

## What this setup does

- Enables `nix.distributedBuilds` on the desktop and laptop
- Uses `ssh-ng` with a dedicated `nix-ssh` account on the NixOS workers
- Pushes completed build outputs to the homelab over SSH so `nix-serve` can publish them
- Adds a local cache substituter pointing at the homelab
- Restricts the NixOS SSH builder port to `192.168.8.0/24`
- Tags only the march-optimized derivations that actually execute build-time target binaries with `requiredSystemFeatures = [ "march-..." ]`

That last point is deliberate. In the current nixpkgs revision, these optimized derivations execute freshly built target binaries during their build:

- `ripgrep`: `cargo test` runs target executables, and the derivation also runs the built `rg` binary in `postFixup` and `installCheck`
- `fd`: `cargo test` runs target executables, and the derivation also runs the built `fd` binary to generate completions in `postInstall`
- `ffmpeg`: enables `doCheck`, and `make check` runs the FATE targets against the built `ffmpeg` and `ffprobe` programs
- `pipewire`: Meson `doCheck` runs compiled SPA/PipeWire test and benchmark executables
- `texlive` environment builders such as `texlive.combined.scheme-medium`: `build-tex-env.sh` exports `$out/bin` into `PATH` and runs `fmtutil`, `updmap-sys`, ConTeXt generation, and related helpers that drive the just-built TeX engines

Other optimized packages stay untagged. In particular, `lsp-plugins` remains distributable because its derivation relies on stdenv's default check phase, but the top-level Makefile has no `check` or `test` target, so no target binaries are executed during the build.

Because of that, `-march=alderlake` or `-march=rocketlake` outputs are not safe to build on an older CPU just because the compiler itself runs there.

## One-time data to collect

1. On `desktop` and `laptop`, run:

   ```bash
   ./scripts/ensure-nix-builder-key.sh
   ```

   This creates `/root/.ssh/id_ed25519_nix_remote_build` if it does not exist, prints the root builder public key, and prints the machine's base64-encoded SSH host key.

2. On the homelab, follow `docs/homelab-builder-setup.md`, then collect:

   - the base64-encoded SSH host key
   - the `homelab-cache-1:...` public cache signing key

3. Update `system/distributed-builds-data.nix`:

   - put the desktop and laptop root builder public keys into `authorizedKeys`
   - put the desktop, laptop, and homelab base64 host keys into `publicHostKeys`
   - put the homelab cache signing key into `cachePublicKey`
   - replace the current hostnames/IPs with DHCP-reserved addresses or stable local DNS names

## Deploy order

1. Set up the homelab first.
2. Rebuild `desktop`.
3. Rebuild `laptop`.

## Smoke tests

From each NixOS machine, test the remote stores explicitly:

```bash
sudo nix store info --store 'ssh-ng://nix-ssh@laptop.local?ssh-key=/root/.ssh/id_ed25519_nix_remote_build'
sudo nix store info --store 'ssh-ng://nix-ssh@desktop.local?ssh-key=/root/.ssh/id_ed25519_nix_remote_build'
sudo nix store info --store 'ssh-ng://nix-ssh@192.168.8.153?ssh-key=/root/.ssh/id_ed25519_nix_remote_build'
curl http://192.168.8.153:5000/nix-cache-info
```

After that, `nixos-rebuild` and `nix build` should start scheduling generic `x86_64-linux` work across the other two builders while leaving march-locked derivations on the matching CPU.
