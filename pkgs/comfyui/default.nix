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
  # 3.14 is the nixpkgs default, but upstream only calls 3.13 "very well
  # supported" and warns that custom nodes break on 3.14.
  python = python313.override {
    self = python;
    packageOverrides = import ./python-packages.nix {
      inherit lib;
      cudaPackages = cudaPackages_13_3;
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
  version = "0.31.0";

  src = fetchFromGitHub {
    owner = "comfyanonymous";
    repo = "ComfyUI";
    tag = "v${finalAttrs.version}";
    hash = "sha256-X4i9sSX6veYmWrcfBxu7OX9fR55qcFbSaEr5jdpwTV4=";
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
