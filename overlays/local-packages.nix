final: prev: {
  cantarell-fonts = prev.cantarell-fonts.overrideAttrs (old: {
    # The variable OTF autohint step fails on the current nixpkgs pin; static
    # OTFs preserve the family without depending on that broken target.
    mesonFlags = (old.mesonFlags or []) ++ [
      "-Dbuildvf=false"
      "-Dbuildstatics=true"
    ];
  });

  bambu-studio = final.callPackage ../pkgs/bambu-studio {
    upstreamBambuStudio = prev.bambu-studio;
  };
  comfyui = final.callPackage ../pkgs/comfyui { };
  desktopctl = final.callPackage ../desktopctl { };
  helium = final.callPackage ../pkgs/helium { };
  i8kutils = final.callPackage ../pkgs/i8kutils { };
  lmstudio = final.callPackage ../pkgs/lmstudio {
    upstreamLmstudio = prev.lmstudio;
  };
  neuwaita = final.callPackage ../pkgs/neuwaita { };
  sf-pro = final.callPackage ../pkgs/sf-pro { };
  snappy-switcher = final.callPackage ../pkgs/snappy-switcher { };
}
