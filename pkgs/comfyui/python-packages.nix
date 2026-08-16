/*
  Python package set adjustments for ComfyUI.

  Two jobs:

  1. Point `torch`/`torchvision`/`torchaudio` at the upstream `-bin` wheels.
     Building them from source with `cudaSupport` pulls in a full pytorch and
     triton-llvm compile; the wheels ship CUDA already and only need unpacking.
     nixpkgs marks `torch-bin` broken against the default CUDA 12 set because
     PyTorch 2.12 wants `cuda-bindings >= 13.0.3`, and its own error message
     says to override `cudaPackages` — that is what `cudaPackages` here is for.

  2. Add the ComfyUI runtime dependencies that nixpkgs does not carry. All of
     them are published as wheels only, so they are unpacked rather than built.
*/
{ lib, cudaPackages }:

final: prev:

let
  fetchWheel =
    { url, hash, ... }@args:
    final.buildPythonPackage (
      (removeAttrs args [
        "url"
        "hash"
      ])
      // {
        format = "wheel";
        src = prev.pkgs.fetchurl { inherit url hash; };
      }
    );

  comfyuiWorkflowTemplatesMeta = {
    description = "Example workflow templates bundled with ComfyUI";
    homepage = "https://github.com/Comfy-Org/workflow_templates";
    license = lib.licenses.gpl3Only;
  };
in
{
  cuda-bindings = prev.cuda-bindings.override { inherit cudaPackages; };

  # The wheel's metadata caps setuptools below 82; nixpkgs is on 83. The cap
  # only guards `torch.utils.cpp_extension`, which nothing on the ComfyUI
  # import path touches, and no older setuptools exists in this package set.
  torch-bin = (prev.torch-bin.override { inherit cudaPackages; }).overridePythonAttrs (
    old: {
      pythonRelaxDeps = (old.pythonRelaxDeps or [ ]) ++ [ "setuptools" ];
    }
  );
  torchvision-bin = prev.torchvision-bin.override { inherit cudaPackages; };
  # nixpkgs pairs cu130 torch/torchvision wheels with the cu128 torchaudio
  # wheel, whose ELFs want libcudart.so.12 and so cannot be patched against a
  # CUDA 13 set. Upstream publishes the same 2.11.0 for cu130; take that one.
  torchaudio-bin = (prev.torchaudio-bin.override { inherit cudaPackages; }).overridePythonAttrs (
    _: {
      src = prev.pkgs.fetchurl {
        url = "https://download.pytorch.org/whl/cu130/torchaudio-2.11.0%2Bcu130-cp313-cp313-manylinux_2_28_x86_64.whl";
        hash = "sha256-6cB8/atpFFQJL/EtId0UB6S7itCB048iLPb89qvMGMg=";
      };
    }
  );

  torch = final.torch-bin;
  torchvision = final.torchvision-bin;
  torchaudio = final.torchaudio-bin;

  comfyui-frontend-package = fetchWheel {
    pname = "comfyui_frontend_package";
    version = "1.48.7";
    url = "https://files.pythonhosted.org/packages/fd/77/f6e2aea61ed41b6e4e9211a0354a947a1504d52982e401d1897f63024dfe/comfyui_frontend_package-1.48.7-py3-none-any.whl";
    hash = "sha256-8ZM2nEJIv/4LFQ3KnLpegvfDrdZkWZE3epktUDauqOc=";
    pythonImportsCheck = [ "comfyui_frontend_package" ];
    meta = {
      description = "Prebuilt ComfyUI web frontend";
      homepage = "https://github.com/Comfy-Org/ComfyUI_frontend";
      license = lib.licenses.gpl3Only;
    };
  };

  # Upstream splits the templates across one metapackage and seven
  # distributions: the loader, the workflow JSON, and five buckets of preview
  # media that make up nearly all of the ~400 MB. ComfyUI degrades to an empty
  # template browser without them, so all of them are packaged.
  comfyui-workflow-templates-core = fetchWheel {
    pname = "comfyui_workflow_templates_core";
    version = "0.3.312";
    url = "https://files.pythonhosted.org/packages/c6/12/d1ef6c177e847d0291bbd6bf6fbb4440fb8df133b1bcae964c35d8237fdf/comfyui_workflow_templates_core-0.3.312-py3-none-any.whl";
    hash = "sha256-22UM+Fac5TFhSs9IHD8+5l2gt0oj1Z4gZENICsgMXxQ=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates-json = fetchWheel {
    pname = "comfyui_workflow_templates_json";
    version = "0.1.47";
    url = "https://files.pythonhosted.org/packages/8f/96/996c53c15cd13d4641e848c0ba6142cf58235cf91e2eb67bee5a4b14bdf1/comfyui_workflow_templates_json-0.1.47-py3-none-any.whl";
    hash = "sha256-mVAmaYATOsXwLZzep4TsV8pUgcZL18F7ZaWo2UX2/e0=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates-media-api = fetchWheel {
    pname = "comfyui_workflow_templates_media_api";
    version = "0.3.84";
    url = "https://files.pythonhosted.org/packages/35/47/e4c723615b396f75893049af38a4b53bcb0e8944418819bb0e0d72f342e8/comfyui_workflow_templates_media_api-0.3.84-py3-none-any.whl";
    hash = "sha256-wtalmZrDnk839HriMcklV97+Wt2yzGq1wRQQtNWikQo=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates-media-video = fetchWheel {
    pname = "comfyui_workflow_templates_media_video";
    version = "0.3.101";
    url = "https://files.pythonhosted.org/packages/e5/9e/49e1fbe9f05df7e4410a8d485af2a2d6fe80b247d44b3bfa7166c54012ef/comfyui_workflow_templates_media_video-0.3.101-py3-none-any.whl";
    hash = "sha256-YnD9YcjDkxtvADGrrH1MkM7WJN5seRi/+FuJ5sPXSTw=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates-media-image = fetchWheel {
    pname = "comfyui_workflow_templates_media_image";
    version = "0.3.160";
    url = "https://files.pythonhosted.org/packages/bd/2e/aa57dc75cc2a73921d8472a398678e1ac40c011756ad0ab2dfe41eb0ba15/comfyui_workflow_templates_media_image-0.3.160-py3-none-any.whl";
    hash = "sha256-1KXFVBxwiPatscfaQfXXwcFKA37aamHNi0t2wlH6qpM=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates-media-other = fetchWheel {
    pname = "comfyui_workflow_templates_media_other";
    version = "0.3.229";
    url = "https://files.pythonhosted.org/packages/a7/46/feed5492a2def46fee71a52fcbb3b7443a048e402c40bedfaaebcc6fa234/comfyui_workflow_templates_media_other-0.3.229-py3-none-any.whl";
    hash = "sha256-zj2Y+p2EuRTDNf5cm8kDz+++GTKxvDy2uu9/NxtL1DU=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates-media-assets-01 = fetchWheel {
    pname = "comfyui_workflow_templates_media_assets_01";
    version = "0.1.28";
    url = "https://files.pythonhosted.org/packages/03/9b/d06af3c2be67040704231720f2b69f9f91bf349d70b163c0c45b54694c85/comfyui_workflow_templates_media_assets_01-0.1.28-py3-none-any.whl";
    hash = "sha256-hZE75UqqunKYKUgOIjlYcD5A3TS3vqIlKxX+d5cu+18=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates = fetchWheel {
    pname = "comfyui_workflow_templates";
    version = "0.11.41";
    url = "https://files.pythonhosted.org/packages/65/ce/13f2fe0eb2079a7d1effe3cfe95b0b56a31c0f7e28bac77aedae5d99e29e/comfyui_workflow_templates-0.11.41-py3-none-any.whl";
    hash = "sha256-1aolKqZsGWR1P5J0NniiFimtjI8BvoQ8cuA+BYisMKU=";
    dependencies = with final; [
      comfyui-workflow-templates-core
      comfyui-workflow-templates-json
      comfyui-workflow-templates-media-api
      comfyui-workflow-templates-media-assets-01
      comfyui-workflow-templates-media-image
      comfyui-workflow-templates-media-other
      comfyui-workflow-templates-media-video
    ];
    pythonImportsCheck = [ "comfyui_workflow_templates" ];
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-embedded-docs = fetchWheel {
    pname = "comfyui_embedded_docs";
    version = "0.5.9";
    url = "https://files.pythonhosted.org/packages/45/6a/95761ec1c888bf64ae554225892dbf934a67dd24dc44591a066890def34e/comfyui_embedded_docs-0.5.9-py3-none-any.whl";
    hash = "sha256-MK+uQypxyWqllCHQ83OIxm/2VyuMvu6P8EXk1fhPiWw=";
    pythonImportsCheck = [ "comfyui_embedded_docs" ];
    meta = {
      description = "Per-node documentation served by the ComfyUI frontend";
      homepage = "https://github.com/Comfy-Org/embedded-docs";
      license = lib.licenses.gpl3Only;
    };
  };

  spandrel = fetchWheel {
    pname = "spandrel";
    version = "0.4.2";
    url = "https://files.pythonhosted.org/packages/74/31/411ea965835534c43d4b98d451968354876e0e867ea1fd42669e4cca0732/spandrel-0.4.2-py3-none-any.whl";
    hash = "sha256-bJPj7L6w5Uj9LfRaYFRys0wWFCh8VrUbszze965SNbU=";
    dependencies = with final; [
      einops
      numpy
      safetensors
      torch
      torchvision
      typing-extensions
    ];
    pythonImportsCheck = [ "spandrel" ];
    meta = {
      description = "Single-model-per-architecture loader for PyTorch super-resolution models";
      homepage = "https://github.com/chaiNNer-org/spandrel";
      license = lib.licenses.mit;
    };
  };

  # Required unconditionally by ComfyUI's main.py; both shipped .so files
  # dlopen the CUDA/ROCm driver rather than linking it.
  comfy-aimdo = fetchWheel {
    pname = "comfy_aimdo";
    version = "0.4.13";
    url = "https://files.pythonhosted.org/packages/a5/ea/ca02387a76cc30fdc0df3e7574199c81f5805b622b835473e76001bae82d/comfy_aimdo-0.4.13-cp39-abi3-manylinux2010_x86_64.manylinux2014_x86_64.manylinux_2_12_x86_64.manylinux_2_17_x86_64.whl";
    hash = "sha256-kY9VqQL7G92EC0ip2jOZZqucRbLq7K2VmZFnxG4fbyA=";
    nativeBuildInputs = with prev.pkgs; [
      autoPatchelfHook
      autoAddDriverRunpath
    ];
    dependencies = [ final.torch ];
    pythonImportsCheck = [ "comfy_aimdo" ];
    meta = {
      description = "AI Model Dynamic Offloader for ComfyUI";
      homepage = "https://github.com/Comfy-Org/comfy-aimdo";
      license = lib.licenses.gpl3Only;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };

  # Optional: ComfyUI degrades to "no fp8/fp4 support" without it.
  comfy-kitchen = fetchWheel {
    pname = "comfy_kitchen";
    version = "0.2.31";
    url = "https://files.pythonhosted.org/packages/db/5d/7df83ccb2b3fc4b9660dd337dcc56f7c65926318ae0303840a1e5b72493d/comfy_kitchen-0.2.31-cp312-abi3-manylinux_2_24_x86_64.manylinux_2_28_x86_64.whl";
    hash = "sha256-18JSLmps3npzA+MNc5wFmJz0sKJGaE5JahKblQBV018=";
    nativeBuildInputs = with prev.pkgs; [
      autoPatchelfHook
      autoAddDriverRunpath
    ];
    buildInputs = [ prev.pkgs.stdenv.cc.cc.lib ];
    # The wheel carries one shared object per compute backend. Only the backend
    # actually selected at runtime is loaded, so the ROCm one may keep its
    # unresolved HIP runtime on this CUDA-only package set.
    autoPatchelfIgnoreMissingDeps = [ "libamdhip64.so.7" ];
    dependencies = [ final.torch ];
    pythonImportsCheck = [ "comfy_kitchen" ];
    meta = {
      description = "Fast kernel library for ComfyUI with multiple compute backends";
      homepage = "https://github.com/Comfy-Org/comfy-kitchen";
      license = lib.licenses.asl20;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };

  # Optional: backs the GLSL nodes in comfy_extras, which ComfyUI skips if the
  # import fails.
  comfy-angle = fetchWheel {
    pname = "comfy_angle";
    version = "0.1.0";
    url = "https://files.pythonhosted.org/packages/94/79/09033953c3f2ef3d31e7cd626e01db9cdd2760a50bb22b83fa6aef32561e/comfy_angle-0.1.0-py3-none-manylinux_2_28_x86_64.whl";
    hash = "sha256-L00X6YQ1PTfSR/r0c6+6vbmGP8OvPgIG+7fYK9wjrGc=";
    nativeBuildInputs = with prev.pkgs; [
      autoPatchelfHook
      autoAddDriverRunpath
    ];
    buildInputs = with prev.pkgs; [
      libglvnd
      stdenv.cc.cc.lib
    ];
    pythonImportsCheck = [ "comfy_angle" ];
    meta = {
      description = "Redistributable ANGLE libraries";
      homepage = "https://github.com/Comfy-Org/comfy-angle";
      license = lib.licenses.bsd3;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    };
  };
}
