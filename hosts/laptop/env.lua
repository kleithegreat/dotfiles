-- Environment Variables — Laptop (hybrid Intel + NVIDIA)

-- GPU — Intel Iris Xe as primary, NVIDIA as secondary
hl.env("LIBVA_DRIVER_NAME", "iHD")
hl.env("AQ_DRM_DEVICES", "/dev/dri/card2:/dev/dri/card1")
-- __EGL_VENDOR_LIBRARY_FILENAMES is set in the host NixOS modules, not here.
