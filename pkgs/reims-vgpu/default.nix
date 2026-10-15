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
}:

rustPlatform.buildRustPackage {
  pname = "reims-vgpu";
  version = "0-unstable-2026-10-14";

  src = fetchFromGitHub {
    owner = "steelbrain";
    repo = "reims-vgpu";
    rev = "c099dd5a4d61107a5527efc64cf1d1ab2f3a9b85";
    hash = "sha256-0yIGDFbLT8m8RdHZ9CzXp41YquWL0GLFqMszXsRf+Ok=";
  };

  # Upstream's committed Cargo.lock leaves out the `source` of its git
  # dependencies and lets cargo add them at build time. See docs/macos-vm.md.
  cargoPatches = [ ./cargo-lock-git-sources.patch ];
  cargoHash = "sha256-Vetkev+s5aU/8WDfhJLdnoXUelbkePsjGUEgcGjgd/c=";

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
  # wants all three of these (egl.pc included), and with libx11 present it
  # would demand every X11 extension too.
  buildInputs = [
    wayland
    libxkbcommon
    libGL
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
