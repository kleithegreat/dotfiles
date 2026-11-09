{
  lib,
  rustPlatform,
  fetchFromGitHub,
  llvmPackages,
  cmake,
  pkg-config,
  wayland,
  wayland-scanner,
  libxkbcommon,
  libGL,
  rust-jemalloc-sys,
}:

rustPlatform.buildRustPackage {
  pname = "reims-vgpu";
  version = "0-unstable-2026-10-29";

  src = fetchFromGitHub {
    owner = "steelbrain";
    repo = "reims-vgpu";
    rev = "1fe0acb68b287db36f1e6c7b9f45383940b8a76f";
    hash = "sha256-g3U/IOTdZcxomBcCEexnnNn/FyD5XsigjTM1SWZdUtk=";
  };

  # Upstream's committed Cargo.lock leaves out the `source` of its git
  # dependencies and lets cargo add them at build time. See docs/macos-vm.md.
  cargoPatches = [ ./cargo-lock-git-sources.patch ];
  cargoHash = "sha256-Ifcjh4JN/b3Z1+UFEZxc6AiYZF4I0sX5njeR2LgXrZI=";

  nativeBuildInputs = [
    cmake
    pkg-config
    wayland-scanner
    # The option ROM: freestanding x86_64-unknown-windows objects, linked with
    # lld-link, which the cc-wrapper's hardening flags would break.
    llvmPackages.clang-unwrapped
    llvmPackages.lld
  ];

  # SDL3 is built from source into the archive, Wayland-only: its Wayland check
  # wants wayland, libxkbcommon and libGL (egl.pc included), and with libx11
  # present it would demand every X11 extension too.
  buildInputs = [
    wayland
    libxkbcommon
    libGL
    rust-jemalloc-sys
  ];

  dontUseCmakeConfigure = true;

  # metal2vulkan's build script hashes its sibling crate through the manifest's
  # `path = "../metal2vulkan-air"`, the git checkout's name for it; the vendor
  # directory names it by version.
  preBuild = /* bash */ ''
    git="$NIX_BUILD_TOP/$(stripHash "$cargoDeps")/source-git-0"
    chmod u+w "$git"
    ln --symbolic metal2vulkan-air-0.2.0 "$git/metal2vulkan-air"
  '';

  buildPhase = /* bash */ ''
    runHook preBuild
    cargo xtask dist --out dist
    runHook postBuild
  '';

  installPhase = /* bash */ ''
    runHook preInstall
    cp --recursive dist "$out"
    runHook postInstall
  '';

  doCheck = false;

  meta = {
    description = "Host side of an experimental paravirtual GPU for macOS guests";
    homepage = "https://reims-vgpu.com/";
    license = with lib.licenses; [
      gpl2Plus
      lgpl3Plus
    ];
    platforms = [ "x86_64-linux" ];
  };
}
