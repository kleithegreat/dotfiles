{
  lib,
  stdenvNoCC,
  coreutils,
  fetchFromGitHub,
  python313,
  cudaPackages_13_3,
  # The store interpreter cannot pip-install custom nodes' dependencies.
  extraPythonPackages ? (ps: [ ]),
}:

let
  # Upstream warns custom nodes break on 3.14, the nixpkgs default.
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
  version = "0.41.0-unstable-2026-10-17";

  src = fetchFromGitHub {
    owner = "comfyanonymous";
    repo = "ComfyUI";
    rev = "c9ea36b9d2140c89b2ef84f93f428df474e72ba5";
    hash = "sha256-XU62/LTN48WSVKUH8RsZ9tbSVVdHi3VvUKnz5akcmAo=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = /* bash */ ''
    runHook preInstall

    mkdir --parents "$out/share/comfyui"
    cp --recursive ./. "$out/share/comfyui"

    skeletonDirs=""
    for dir in $(find models input output custom_nodes -type d | sort); do
      skeletonDirs="$skeletonDirs \"\$base_directory/$dir\""
    done

    install -D --mode=0755 ${./comfyui.sh} "$out/bin/comfyui"
    substituteInPlace "$out/bin/comfyui" \
      --replace-fail '@mkdir@' '${lib.getExe' coreutils "mkdir"}' \
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
