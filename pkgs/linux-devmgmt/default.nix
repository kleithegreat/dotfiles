{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6,
  kmod,
  bluez,
  upower,
  libimobiledevice,
  usbmuxd,
  hwdata,
  libdrm,
}:

stdenv.mkDerivation {
  pname = "linux-devmgmt";
  version = "2.1.1";

  src = fetchFromGitHub {
    owner = "actuallyaridan";
    repo = "linux-devmgmt";
    tag = "v2.1.1";
    hash = "sha256-49i9mEk3XS6TiPYo/2XXAtsInv37QvTH4hUP7Po22xc=";
  };

  nativeBuildInputs = [
    cmake
    qt6.wrapQtAppsHook
  ];
  buildInputs = [ qt6.qtbase ];

  # Suffixed so the system's tools win; pkexec must come from /run/wrappers.
  qtWrapperArgs = [
    "--suffix" "PATH" ":" (lib.makeBinPath [ kmod bluez upower libimobiledevice usbmuxd ])
    "--set" "HWDATA_DIR" "${hwdata}/share/hwdata"
    "--set" "LIBDRM_DIR" "${libdrm}/share/libdrm"
  ];

  meta = with lib; {
    description = "Recreation of the Windows Device Manager on sysfs";
    homepage = "https://github.com/actuallyaridan/linux-devmgmt";
    license = licenses.gpl3Only;
    mainProgram = "devmgmt";
    platforms = platforms.linux;
  };
}
