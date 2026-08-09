-- Environment Variables — Desktop (dedicated NVIDIA)

hl.env("DESKTOPCTL_IDLE_INHIBIT_DEFAULT", "1")

-- GPU — dedicated NVIDIA
hl.env("LIBVA_DRIVER_NAME", "nvidia")
hl.env("GBM_BACKEND", "nvidia-drm")
hl.env("__GLX_VENDOR_LIBRARY_NAME", "nvidia")
hl.env("NVD_BACKEND", "direct")
