{
  lib,
  optimize,
  qemu_kvm,
  fetchFromGitHub,
  fetchFromGitLab,
  reims-vgpu,
  vulkan-loader,
  wayland,
  libxkbcommon,
}:

let
  # The rev this tree's `subprojects/keycodemapdb.wrap` names; see docs/macos-vm.md.
  keycodemapdb = fetchFromGitLab {
    owner = "qemu-project";
    repo = "keycodemapdb";
    rev = "f5772a62ec52591ff6870b7e8ef32482371f22c6";
    hash = "sha256-GbZ5mrUYLXMi0IX4IZzles0Oyc095ij2xAsiLNJwfKQ=";
  };

  # dlopened by `ash` and SDL3, so absent from RUNPATH.
  runtimeLibs = [
    vulkan-loader
    wayland
    libxkbcommon
  ];
in
((optimize.ccache qemu_kvm).override {
  enableDocs = false;
  # macOS has no qemu-ga, and dropping it drops the one nixpkgs patch that
  # only it needed.
  guestAgentSupport = false;
}).overrideAttrs
  (old: {
    pname = "qemu-reims-vgpu";
    version = "11.1.50-unstable-2026-10-14";

    # The commit `vendor/qemu` names in reims-vgpu's pinned rev.
    src = fetchFromGitHub {
      owner = "steelbrain";
      repo = "qemu-reims-vgpu";
      rev = "fbda9c8b28351baab659dbd8e591914f44ee7fdb";
      hash = "sha256-RYXypniM/Nn1t0q+r/v2TQ3nziEhKEVQ4Noi72paLQ8=";
    };

    # nixpkgs' patches are cut against the 11.1.2 release; this fork is
    # upstream master, which already carries some of them.
    patches = [ ];

    postUnpack = /* bash */ ''
      cp --recursive ${keycodemapdb} "$sourceRoot/subprojects/keycodemapdb"
      chmod --recursive u+w "$sourceRoot/subprojects/keycodemapdb"
    '';

    buildInputs = old.buildInputs ++ [ reims-vgpu ];

    configureFlags = old.configureFlags ++ [
      # `auto` would quietly build a QEMU without the device if pkg-config
      # missed the library.
      "--enable-pvg"
      # Both keep wraps from reaching for the network; see docs/macos-vm.md.
      "--disable-download"
      "--disable-tcg"
    ];

    preFixup = /* bash */ ''
      gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath runtimeLibs})
    '';

    passthru = { };

    meta = old.meta // {
      description = "QEMU carrying apple-gfx on reims-vgpu, an experimental paravirtual GPU for macOS guests";
      homepage = "https://github.com/steelbrain/qemu-reims-vgpu";
      mainProgram = "qemu-system-x86_64";
      platforms = [ "x86_64-linux" ];
    };
  })
