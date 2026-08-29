{
  lib,
  qemu_kvm,
  fetchFromGitHub,
  fetchFromGitLab,
  rustPlatform,
  cargo,
  rustc,
  vulkan-loader,
  wayland,
  libxkbcommon,
  libx11,
  libxcursor,
  libxi,
  libxrandr,
  llvm,
  spirv-tools,
}:

let
  # Four pins that move as one: `qemuSrc` is what `vendor/qemu` points at in
  # this `src` rev, `keycodemapdb` is the revision named by that tree's
  # `subprojects/keycodemapdb.wrap`, and `outputHashes` covers the one git
  # dependency in `Cargo.lock`. Upstream promises no ABI compatibility between
  # revisions, so a half-bumped set links a device the other half cannot speak
  # to. See docs/macos-vm.md.
  src = fetchFromGitHub {
    owner = "steelbrain";
    repo = "reims-vgpu";
    rev = "d031507ff092dd9b2be03cafee00435dd82e2997";
    hash = "sha256-2Hr/c3wqkgsMvrG5n4KNwtxwO2Bw6QItf7GpOBxmVv0=";
  };

  qemuSrc = fetchFromGitHub {
    owner = "steelbrain";
    repo = "qemu-reims-vgpu";
    rev = "e17ddb98f71df5697daf2f830587f672a8f4f5a7";
    hash = "sha256-XFxXzSYRhq3x/KeM+98QiUPN8DP9AZ2fIL+JUFiBxzQ=";
  };

  # QEMU resolves this one through a meson wrap, which downloads. The build has
  # no network, so it arrives as a source instead.
  keycodemapdb = fetchFromGitLab {
    owner = "qemu-project";
    repo = "keycodemapdb";
    rev = "f5772a62ec52591ff6870b7e8ef32482371f22c6";
    hash = "sha256-GbZ5mrUYLXMi0IX4IZzles0Oyc095ij2xAsiLNJwfKQ=";
  };

  # `metal2vulkan` spawns these once per uncached shader, so they have to be on
  # QEMU's own PATH. See docs/macos-vm.md.
  shaderTools = [
    llvm
    spirv-tools
  ];

  # `ash` and `winit` reach these through dlopen, so no DT_NEEDED entry names
  # them and nothing puts them in the binary's RUNPATH.
  runtimeLibs = [
    vulkan-loader
    wayland
    libxkbcommon
    libx11
    libxcursor
    libxi
    libxrandr
  ];
in
(qemu_kvm.override {
  enableDocs = false;
  # macOS has no qemu-ga, and dropping it drops the nixpkgs patch that carries
  # it — which is cut against the 11.0.2 release this tree has moved past.
  guestAgentSupport = false;
}).overrideAttrs (old: {
  pname = "reims-vgpu";
  version = "0-unstable-2026-08-28";

  inherit src;

  # `hw/display/meson.build` reaches the device's Rust half as
  # `meson.global_source_root() / '..' / '..'` and builds it with cargo, so
  # QEMU has to sit at `vendor/qemu` inside the reims-vgpu checkout rather
  # than be the source root. The source root stays the outer tree — that is
  # where `Cargo.lock` is, which is what `cargoSetupHook` validates against —
  # and preConfigure descends before anything QEMU-relative runs.
  unpackPhase = ''
    runHook preUnpack

    # Every destination is created first and every copy names contents
    # (`/.`), so each one lands in a directory that is already writable —
    # `vendor/qemu` is in the tarball as an empty directory, and cp would
    # otherwise nest a second level under it. Modes survive the copy because
    # `configure` and the meson helper scripts have to stay executable;
    # replacing the unpack phase means the writable bit is ours to set.
    mkdir --parents reims-vgpu/vendor/qemu/subprojects/keycodemapdb
    cp --recursive --no-preserve=ownership ${src}/. reims-vgpu/
    cp --recursive --no-preserve=ownership ${qemuSrc}/. reims-vgpu/vendor/qemu/
    cp --recursive --no-preserve=ownership ${keycodemapdb}/. \
      reims-vgpu/vendor/qemu/subprojects/keycodemapdb/
    chmod --recursive u+w reims-vgpu

    runHook postUnpack
  '';

  sourceRoot = "reims-vgpu";

  # nixpkgs' patches are cut against the 11.0.2 release; this fork is 11.0.50.
  patches = [ ];

  postPatch = ''
    sed -i "/install_emptydir(get_option('localstatedir') \/ 'run')/d" \
      vendor/qemu/qga/meson.build
  '';

  cargoDeps = rustPlatform.importCargoLock {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "metal2vulkan-0.1.0" = "sha256-hK9CXZsXC555Ey/2vetqnFxKIF4hLqeqOnvI70uJNNs=";
    };
  };

  nativeBuildInputs = old.nativeBuildInputs ++ [
    cargo
    rustc
    rustPlatform.cargoSetupHook
  ];

  preConfigure = ''
    unset CPP # interferes with dependency calculation
    chmod +x vendor/qemu/scripts/shaderinclude.py
    patchShebangs vendor/qemu
    cd vendor/qemu
  '';

  configureFlags = old.configureFlags ++ [
    # The backend is a configure-time choice baked into the binary; the device
    # never sniffs the environment for it, and `metal` is Apple-only.
    "-Dreims_vgpu_backend=vulkan"
    # Turns a wrap download into a configure error instead of a build that
    # reaches for the network it does not have.
    "--disable-download"
    # Every guest this binary exists for runs under KVM, and dropping TCG takes
    # QEMU's softfloat test suite with it — the last thing in the tree that
    # wanted a wrap checked out by hand.
    "--disable-tcg"
  ];

  preFixup = ''
    gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs})
    gappsWrapperArgs+=(--prefix PATH : ${lib.makeBinPath shaderTools})
  '';

  passthru = { };

  meta = old.meta // {
    description = "QEMU carrying reims-vgpu, an experimental paravirtual GPU for macOS guests";
    homepage = "https://reims-vgpu.com/";
    license = with lib.licenses; [
      gpl2Plus
      lgpl3Plus
    ];
    mainProgram = "qemu-system-x86_64";
    platforms = [ "x86_64-linux" ];
  };
})
