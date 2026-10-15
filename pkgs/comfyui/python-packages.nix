/*
  Python package set adjustments for ComfyUI.

  Two jobs:

  1. Point `torch`/`torchvision` at the upstream `-bin` wheels.
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

  torch = final.torch-bin;
  torchvision = final.torchvision-bin;

  comfyui-frontend-package = fetchWheel {
    pname = "comfyui_frontend_package";
    version = "1.55.17";
    url = "https://files.pythonhosted.org/packages/30/82/bc354e027b8a31714c9870999bd67f95e2079d7c5c768f4e4346baea8aae/comfyui_frontend_package-1.55.17-py3-none-any.whl";
    hash = "sha256-2Qw19HDnVwzzVVKgzRYDR77uBsc4BfFuGPkqhlDtsAg=";
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
    version = "0.3.373";
    url = "https://files.pythonhosted.org/packages/cc/ab/1299a0a5ce6e93a38169417cf1f1779325bfbaaf8204247c0428aa4e5eaf/comfyui_workflow_templates_core-0.3.373-py3-none-any.whl";
    hash = "sha256-KOhNOmiwGO5k+ttJd5s3dr6c4/BP4ZLQ4cVgDUVAdzY=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates-json = fetchWheel {
    pname = "comfyui_workflow_templates_json";
    version = "0.1.108";
    url = "https://files.pythonhosted.org/packages/6d/87/28459ec38d482d4b0338dba10b2ad9e98b9ddba72b67f44f447a2f7432ea/comfyui_workflow_templates_json-0.1.108-py3-none-any.whl";
    hash = "sha256-W4mafHncAGTvUoLjkdEowTljqicmt1chaNXxf+aO+rI=";
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
    version = "0.1.48";
    url = "https://files.pythonhosted.org/packages/7c/4c/39858b7dd6036fae44e15baf6eb5e55671291d25b9e0931bc0956ce12055/comfyui_workflow_templates_media_assets_01-0.1.48-py3-none-any.whl";
    hash = "sha256-dzPtEoZ+lea4s5viC8xzV5wo6X5aRAhv+5d8wsHHjEM=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates-media-assets-02 = fetchWheel {
    pname = "comfyui_workflow_templates_media_assets_02";
    version = "0.1.14";
    url = "https://files.pythonhosted.org/packages/0a/19/8115931916651ebb3dfcc43ed56244959e72b0aaacec439815f50a398888/comfyui_workflow_templates_media_assets_02-0.1.14-py3-none-any.whl";
    hash = "sha256-3pKIxa99S+XuPT24VE4xSJ8QjIrZ6skheOuvbhJNxk8=";
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-workflow-templates = fetchWheel {
    pname = "comfyui_workflow_templates";
    version = "0.11.82";
    url = "https://files.pythonhosted.org/packages/39/0d/ad05fdf3c742e507840217943b9a9e0e08ac1ffd956f341a470a66c9caf3/comfyui_workflow_templates-0.11.82-py3-none-any.whl";
    hash = "sha256-DEy1bz5HGRy9nUl6CA3TWr7gj3U3LT2oai+dZ2WlcJY=";
    dependencies = with final; [
      comfyui-workflow-templates-core
      comfyui-workflow-templates-json
      comfyui-workflow-templates-media-api
      comfyui-workflow-templates-media-assets-01
      comfyui-workflow-templates-media-assets-02
      comfyui-workflow-templates-media-image
      comfyui-workflow-templates-media-other
      comfyui-workflow-templates-media-video
    ];
    pythonImportsCheck = [ "comfyui_workflow_templates" ];
    meta = comfyuiWorkflowTemplatesMeta;
  };

  comfyui-embedded-docs = fetchWheel {
    pname = "comfyui_embedded_docs";
    version = "0.5.14";
    url = "https://files.pythonhosted.org/packages/21/99/87493c6a2c90801e949a5fc8e2f35acb45a05f79ba779dabd18c5d07dad0/comfyui_embedded_docs-0.5.14-py3-none-any.whl";
    hash = "sha256-6ubCdSG2JDJQrdj6OfMmPfO1Ehc5ov5m/yePJRf0mek=";
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
    version = "0.5.6";
    url = "https://files.pythonhosted.org/packages/0e/31/1b997a83947c56a9cb30398e5ea04bfca553cd1385528a923a3702920984/comfy_aimdo-0.5.6-cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64.whl";
    hash = "sha256-AzK8M7ZFl6/xtPefa7dN89URhBjwjGYhBmWDS0q2JG4=";
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
    version = "0.2.37";
    url = "https://files.pythonhosted.org/packages/19/04/d24939d30b077679bfc8bf4a53c7392f9d8650df7ce69164238a673753a1/comfy_kitchen-0.2.37-cp312-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64.whl";
    hash = "sha256-A8yg0QwxSqoTv/j5Qi0Dl0Iho0QWKyPU8Q0n6yo10Og=";
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
    version = "0.1.1";
    url = "https://files.pythonhosted.org/packages/af/f4/5ddd0416e9619233b20e2a34c47d2359d4ac6b17a17f8bf59e0bfe5b93c3/comfy_angle-0.1.1-py3-none-manylinux_2_28_x86_64.whl";
    hash = "sha256-PS/KuThuu7VlPWZpb6i8rTKcHRhS6kth8obqmUhahAo=";
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
