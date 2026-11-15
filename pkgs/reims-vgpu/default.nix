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

  # Upstream's Cargo.lock omits its git sources (docs/macos-vm.md).
  cargoPatches = [ ./cargo-lock-git-sources.patch ];
  cargoHash = "sha256-Ifcjh4JN/b3Z1+UFEZxc6AiYZF4I0sX5njeR2LgXrZI=";

  nativeBuildInputs = [
    cmake
    pkg-config
    wayland-scanner
    # The option ROM links with lld-link, which the cc-wrapper's hardening flags break.
    llvmPackages.clang-unwrapped
    llvmPackages.lld
  ];

  # SDL3 builds in Wayland-only; with libx11 present it would demand every X11 extension.
  buildInputs = [
    wayland
    libxkbcommon
    libGL
  ];

  # The generated reims-vgpu.pc names `-ljemalloc` for static consumers (QEMU).
  propagatedBuildInputs = [ rust-jemalloc-sys ];

  dontUseCmakeConfigure = true;

  # metal2vulkan's build script finds its sibling by the git checkout's name, not the vendored one.
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
