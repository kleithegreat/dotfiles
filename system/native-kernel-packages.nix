{ lib, pkgs, hostName, enableNativeOptimizations }:

let
  nativeOptimizations = import ./native-optimizations.nix {
    inherit lib hostName enableNativeOptimizations;
  };

  sharedKernelConfig = with lib.kernel; {
    DEFAULT_BBR = lib.mkForce yes;
    DEFAULT_CUBIC = lib.mkForce no;
    DEFAULT_FQ = lib.mkForce yes;
    DEFAULT_FQ_CODEL = lib.mkForce no;
    DEFAULT_TCP_CONG = freeform "\"bbr\"";
    HZ = freeform "1000";
    HZ_1000 = lib.mkForce yes;
    HZ_250 = lib.mkForce no;
    HZ_300 = lib.mkForce no;
    HZ_500 = lib.mkForce no;
    HZ_600 = lib.mkForce no;
    HZ_750 = lib.mkForce no;
    HZ_PERIODIC = lib.mkForce no;
    LRU_GEN = lib.mkForce yes;
    LRU_GEN_ENABLED = lib.mkForce yes;
    LTO_CLANG_FULL = lib.mkForce no;
    LTO_CLANG_THIN = lib.mkForce yes;
    LTO_CLANG_THIN_DIST = lib.mkForce no;
    LTO_NONE = lib.mkForce no;
    NET_SCH_DEFAULT = lib.mkForce yes;
    NET_SCH_FQ = lib.mkForce yes;
    NO_HZ = lib.mkForce yes;
    NO_HZ_COMMON = lib.mkForce yes;
    NO_HZ_FULL = lib.mkForce no;
    NO_HZ_IDLE = lib.mkForce yes;
    SCHED_AUTOGROUP = lib.mkForce yes;
    SCHED_BORE = lib.mkForce yes;
    TCP_CONG_BBR = lib.mkForce yes;
    TRANSPARENT_HUGEPAGE_ALWAYS = lib.mkForce no;
    TRANSPARENT_HUGEPAGE_MADVISE = lib.mkForce yes;
  };

  patchedKernel = pkgs.linux_6_18.override {
    stdenv = pkgs.llvmPackages.stdenv;
    argsOverride = {
      version = "6.18.23";
      modDirVersion = "6.18.23";
      src = pkgs.fetchurl {
        url = "https://github.com/CachyOS/linux/releases/download/cachyos-6.18.23-1/cachyos-6.18.23-1.tar.gz";
        hash = "sha256-xldhTP9ixBmLy9g2iGxazT0byDKf/9KyRXKNZt/MwHc=";
      };
      ignoreConfigErrors = true;
      extraMakeFlags = [
        "LLVM=1"
        "LLVM_IAS=1"
      ];
      kernelPatches = [
        {
          name = "bore-scheduler";
          patch = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/CachyOS/kernel-patches/master/6.18/sched/0001-bore-cachy.patch";
            hash = "sha256-KQ3HeQBDcfcdI/J1iTBm3Xqo1oZKyfXQSEQ3m4VUygw=";
          };
        }
      ];
      structuredExtraConfig = sharedKernelConfig;
      extraMeta = {
        branch = "6.18.23-cachyos-bore";
      };
    };
  };
in
if !nativeOptimizations.enabled then
  pkgs.linuxPackagesFor patchedKernel
else
  pkgs.linuxPackagesFor (patchedKernel.overrideAttrs (old:
    nativeOptimizations.nativeHostAttrs old
    // {
      extraMakeFlags = (old.extraMakeFlags or [ ]) ++ nativeOptimizations.kernelExtraMakeFlags;
    }
  ))
