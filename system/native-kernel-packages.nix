{ lib, pkgs, host, enableNativeOptimizations }:

let
  nativeOptimizations = import ./native-optimizations.nix {
    inherit lib host enableNativeOptimizations;
  };

  boreBasePatch = pkgs.runCommand "0001-bore-stock.patch" {
    nativeBuildInputs = [ pkgs.perl ];
    src = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/CachyOS/kernel-patches/master/6.18/sched/0001-bore.patch";
      hash = "sha256-qirGswbEE1SpopM9FiY60uaZT/cd5hyBLa0OgUj2AYM=";
    };
  } ''
    perl -0e '
      local $/;
      open my $src_fh, "<", $ENV{"src"} or die $!;
      my $text = <$src_fh>;

      $text =~ s/^\@\@ -698,6 \+723,9 \@\@ static void update_entity_lag\(struct cfs_rq \*cfs_rq, struct sched_entity \*se\)\n.*?(?=^\@\@ )//ms
        or die "failed to strip the stock-incompatible BORE hunk\n";

      print $text;
    ' > "$out"
  '';

  boreFairCompatPatch = pkgs.writeText "0002-bore-stock-fair-compat.patch" (
    lib.concatStringsSep "\n" [
      "diff --git a/kernel/sched/fair.c b/kernel/sched/fair.c"
      "--- a/kernel/sched/fair.c"
      "+++ b/kernel/sched/fair.c"
      "@@ -799,6 +799,9 @@ static void update_entity_lag(struct cfs_rq *cfs_rq, struct sched_entity *se)"
      " \tvlag = avg_vruntime(cfs_rq) - se->vruntime;"
      " \tlimit = calc_delta_fair(max_slice, se);"
      "+#ifdef CONFIG_SCHED_BORE"
      "+\tlimit >>= !!sched_bore;"
      "+#endif /* CONFIG_SCHED_BORE */"
      " "
      " \tse->vlag = clamp(vlag, -limit, limit);"
      " }"
      ""
    ]
  );

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
      ignoreConfigErrors = true;
      extraMakeFlags = [
        "LLVM=1"
        "LLVM_IAS=1"
      ];
      kernelPatches = [
        {
          name = "bore-scheduler";
          patch = boreBasePatch;
        }
        {
          name = "bore-stock-fair-compat";
          patch = boreFairCompatPatch;
        }
        {
          name = "bbr3";
          patch = pkgs.fetchurl {
            url = "https://github.com/CachyOS/linux/commit/9744acecba04.patch";
            hash = "sha256-XDyDHLYr4/9vyDqmelMSrqGHcGiyD+fFxHGX6MWXDws=";
          };
        }
      ];
      structuredExtraConfig = sharedKernelConfig;
      extraMeta = {
        branch = "6.18-stock-bore-bbr3";
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
