{
  lib,
  stdenvNoCC,
  coreutils,
  fetchFromGitHub,
  python313,
  cudaPackages_13_3,
  # Custom node packs that need Python dependencies beyond ComfyUI's own
  # requirements get them from here — the store-resident interpreter cannot
  # pip-install at runtime.
  extraPythonPackages ? (ps: [ ]),
}:

let
  # nixpkgs hardcodes NVSHMEM_BUILD_TESTS/EXAMPLES on, so libnvshmem — a full
  # nvcc build we reach only as a torch dependency — also compiles its perftest
  # and example device binaries. Nothing here runs them, and dropping them takes
  # a large slice off a build that is otherwise heavy enough to OOM the laptop.
  # NVSHMEM itself is only used for multi-GPU symmetric memory, which no host
  # here has, but torch links it, so it cannot be dropped outright.
  disableCmakeBool =
    flag: lib.replaceStrings [ "-D${flag}:BOOL=TRUE" ] [ "-D${flag}:BOOL=FALSE" ];

  cudaPackages = cudaPackages_13_3.overrideScope (
    _final: prev: {
      libnvshmem = prev.libnvshmem.overrideAttrs (old: {
        cmakeFlags =
          old.cmakeFlags
          |> map (disableCmakeBool "NVSHMEM_BUILD_TESTS")
          |> map (disableCmakeBool "NVSHMEM_BUILD_EXAMPLES");
      });
    }
  );

  # 3.14 is the nixpkgs default, but upstream only calls 3.13 "very well
  # supported" and warns that custom nodes break on 3.14.
  python = python313.override {
    self = python;
    packageOverrides = import ./python-packages.nix {
      inherit lib cudaPackages;
    };
  };

  pythonEnv = python.withPackages (
    ps:
    (with ps; [
      aiohttp
      alembic
      av
      blake3
      comfy-aimdo
      comfy-angle
      comfy-kitchen
      comfyui-embedded-docs
      comfyui-frontend-package
      comfyui-workflow-templates
      einops
      filelock
      kornia
      numpy
      pillow
      psutil
      pydantic
      pydantic-settings
      pyopengl
      pyyaml
      requests
      safetensors
      scipy
      sentencepiece
      simpleeval
      spandrel
      sqlalchemy
      tokenizers
      torch
      torchaudio
      torchsde
      torchvision
      tqdm
      transformers
      yarl
    ])
    ++ extraPythonPackages ps
  );
in
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "comfyui";
  version = "0.33.1";

  src = fetchFromGitHub {
    owner = "comfyanonymous";
    repo = "ComfyUI";
    tag = "v${finalAttrs.version}";
    hash = "sha256-r6amApYXBjfE8+UvhiJ/7VcUibd4kd5i+JLPXxo8H9w=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/comfyui"
    cp -r ./. "$out/share/comfyui"

    skeletonDirs=""
    for dir in $(find models input output custom_nodes -type d | sort); do
      skeletonDirs="$skeletonDirs \"\$base_directory/$dir\""
    done

    install -Dm0755 ${./comfyui.sh} "$out/bin/comfyui"
    substituteInPlace "$out/bin/comfyui" \
      --replace-fail '@mkdir@' '${coreutils}/bin/mkdir' \
      --replace-fail '@skeletonDirs@' "$skeletonDirs" \
      --replace-fail '@python@' '${pythonEnv}' \
      --replace-fail '@app@' "$out/share/comfyui"

    runHook postInstall
  '';

  passthru = {
    inherit python pythonEnv;
  };

  meta = {
    description = "Node-based diffusion model GUI and backend";
    homepage = "https://github.com/comfyanonymous/ComfyUI";
    license = lib.licenses.gpl3Only;
    mainProgram = "comfyui";
    platforms = [ "x86_64-linux" ];
  };
})
