# Points torch/torchvision at the CUDA 13 `-bin` wheels (docs/nix.md) and adds
# the wheel-only ComfyUI dependencies nixpkgs lacks.
{ lib, cudaPackages }:

final: prev:

let
  # PyPI's legacy path redirects to the hashed one; `tag` is the wheel's
  # python-abi-platform triple.
  fetchWheel =
    {
      pname,
      version,
      hash,
      tag ? "py3-none-any",
      ...
    }@args:
    final.buildPythonPackage (
      (removeAttrs args [
        "hash"
        "tag"
      ])
      // {
        format = "wheel";
        src = prev.pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/${lib.lists.head (lib.strings.splitString "-" tag)}/${lib.strings.substring 0 1 pname}/${pname}/${pname}-${version}-${tag}.whl";
          inherit hash;
        };
      }
    );

  templatesMeta = {
    description = "Example workflow templates bundled with ComfyUI";
    homepage = "https://github.com/Comfy-Org/workflow_templates";
    license = lib.licenses.gpl3Only;
  };
  workflowTemplates =
    suffix: version: hash:
    fetchWheel {
      pname = "comfyui_workflow_templates_${suffix}";
      inherit version hash;
      meta = templatesMeta;
    };
in
{
  cuda-bindings = prev.cuda-bindings.override { inherit cudaPackages; };

  # The setuptools<82 cap guards only `torch.utils.cpp_extension`, unused here.
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
    hash = "sha256-2Qw19HDnVwzzVVKgzRYDR77uBsc4BfFuGPkqhlDtsAg=";
    pythonImportsCheck = [ "comfyui_frontend_package" ];
    meta = {
      description = "Prebuilt ComfyUI web frontend";
      homepage = "https://github.com/Comfy-Org/ComfyUI_frontend";
      license = lib.licenses.gpl3Only;
    };
  };

  # A partial set of the metapackage's parts leaves the template browser empty.
  comfyui-workflow-templates-core = workflowTemplates "core" "0.3.380" "sha256-PppQKYDqWjuGfIFei42cFdyJmtwMxL9TgyIyeq2Vzsw=";
  comfyui-workflow-templates-json = workflowTemplates "json" "0.1.115" "sha256-Tm5gehoGCzLToo2lGFgIeWRwYzYJ4n2+zGQSI5GsI8U=";
  comfyui-workflow-templates-media-api = workflowTemplates "media_api" "0.3.84" "sha256-wtalmZrDnk839HriMcklV97+Wt2yzGq1wRQQtNWikQo=";
  comfyui-workflow-templates-media-video = workflowTemplates "media_video" "0.3.101" "sha256-YnD9YcjDkxtvADGrrH1MkM7WJN5seRi/+FuJ5sPXSTw=";
  comfyui-workflow-templates-media-image = workflowTemplates "media_image" "0.3.160" "sha256-1KXFVBxwiPatscfaQfXXwcFKA37aamHNi0t2wlH6qpM=";
  comfyui-workflow-templates-media-other = workflowTemplates "media_other" "0.3.229" "sha256-zj2Y+p2EuRTDNf5cm8kDz+++GTKxvDy2uu9/NxtL1DU=";
  comfyui-workflow-templates-media-assets-01 = workflowTemplates "media_assets_01" "0.1.48" "sha256-dzPtEoZ+lea4s5viC8xzV5wo6X5aRAhv+5d8wsHHjEM=";
  comfyui-workflow-templates-media-assets-02 = workflowTemplates "media_assets_02" "0.1.17" "sha256-UFFGjJKkYwFtVqkOzAPmflIpn6y0bnJGkIxFAYzdX+0=";

  comfyui-workflow-templates = fetchWheel {
    pname = "comfyui_workflow_templates";
    version = "0.11.89";
    hash = "sha256-1Y0qvWWKoqWZc2qw02by2buTLsjHdmtoBokJO0p5suI=";
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
    meta = templatesMeta;
  };

  comfyui-embedded-docs = fetchWheel {
    pname = "comfyui_embedded_docs";
    version = "0.5.14";
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
    tag = "cp39-abi3-manylinux2014_x86_64.manylinux_2_17_x86_64";
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
    version = "0.2.38";
    tag = "cp312-abi3-manylinux_2_27_x86_64.manylinux_2_28_x86_64";
    hash = "sha256-PgYgsGkzhsRJ2Q8HdyMxnIcqKpghexX60Ac78EBgeR4=";
    nativeBuildInputs = with prev.pkgs; [
      autoPatchelfHook
      autoAddDriverRunpath
    ];
    buildInputs = [ prev.pkgs.stdenv.cc.cc.lib ];
    # Only the selected backend's object loads, so ROCm's may stay unresolved.
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
    tag = "py3-none-manylinux_2_28_x86_64";
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
