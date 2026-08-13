{ lib, dotfilesPath, host, snappySwitcherPkg, bambuStudioPkg }:
{ config, ... }:

let
  dotfilesSource = path: "${dotfilesPath}/${path}";
  # Deploy nvim from the store minus lazy-lock.json, which is instead a
  # writable out-of-store symlink into the repo checkout below so
  # `:Lazy update` writes the committed lock directly (review + commit the
  # diff afterward). Assumes the checkout lives at ~/repos/dotfiles, same as
  # the DESKTOPCTL_REPO fallback in config/hypr/keybinds.lua.
  nvimSource = lib.cleanSourceWith {
    name = "nvim-config";
    src = "${dotfilesPath}/config/nvim";
    filter = path: _type: baseNameOf path != "lazy-lock.json";
  };
  staticConfigSources = lib.mapAttrs (_: source: { inherit source; }) {
    # Hyprland itself is configured in Lua (hyprlang was deprecated in 0.55).
    # hypridle/hyprlock are separate apps and still take hyprlang .conf.
    "hypr/hyprland.lua" = dotfilesSource "config/hypr/hyprland.lua";
    "hypr/appearance.lua" = dotfilesSource "config/hypr/appearance.lua";
    "hypr/env.lua" = dotfilesSource "config/hypr/env.lua";
    "hypr/autostart.lua" = dotfilesSource "config/hypr/autostart.lua";
    "hypr/cursor.lua" = dotfilesSource "config/hypr/cursor.lua";
    "hypr/input.lua" = dotfilesSource "config/hypr/input.lua";
    "hypr/input-defaults.lua" = dotfilesSource "config/hypr/input-defaults.lua";
    "hypr/keybinds.lua" = dotfilesSource "config/hypr/keybinds.lua";
    "hypr/animations-override.lua" = dotfilesSource "config/hypr/animations-override.lua";
    "hypr/rules.lua" = dotfilesSource "config/hypr/rules.lua";
    "hypr/plugins.lua" = dotfilesSource "config/hypr/plugins.lua";
    "hypr/session.lua" = dotfilesSource "config/hypr/session.lua";
    "hypr/hypridle.conf" = dotfilesSource "config/hypr/hypridle.conf";
    "hypr/hyprlock.conf" = dotfilesSource "config/hypr/hyprlock.conf";
    "alacritty/alacritty.toml" = dotfilesSource "config/alacritty/alacritty.toml";
    "ghostty/config" = dotfilesSource "config/ghostty/config";
    "tmux/tmux.conf" = dotfilesSource "config/tmux/tmux.conf";
    "git/ignore" = dotfilesSource "config/git/ignore";
    "vicinae/settings.json" = dotfilesSource "config/vicinae/settings.json";
    "zathura/zathurarc" = dotfilesSource "config/zathura/zathurarc";
  };
  recursiveConfigSources = lib.mapAttrs (_: source: {
    inherit source;
    recursive = true;
  }) {
    quickshell = dotfilesSource "config/quickshell";
    nvim = nvimSource;
  };
  mkHostConfigFile = key: fallback:
    let
      relativePath = host.hyprland.${key};
    in
    if relativePath == null then
      { text = fallback; }
    else
      { source = dotfilesSource relativePath; };

  # Mask noisy per-format / per-backend launchers that show up as duplicates in
  # Nautilus's "Open With" picker. `NoDisplay=true` is ignored by GTK4's all-apps
  # list, so we use `Hidden=true` (XDG: treat as if deleted) via user-level
  # shadows of the system desktop files.
  hiddenDesktopFiles = [
    # Krita ships one launcher per supported file format, all named "Krita".
    # Keep `org.kde.krita.desktop` as the canonical entry.
    "krita_brush.desktop"
    "krita_csv.desktop"
    "krita_exr.desktop"
    "krita_gif.desktop"
    "krita_heif.desktop"
    "krita_heightmap.desktop"
    "krita_jp2.desktop"
    "krita_jpeg.desktop"
    "krita_jxl.desktop"
    "krita_kra.desktop"
    "krita_krz.desktop"
    "krita_ora.desktop"
    "krita_pdf.desktop"
    "krita_png.desktop"
    "krita_psd.desktop"
    "krita_qimageio.desktop"
    "krita_raw.desktop"
    "krita_rgbe.desktop"
    "krita_spriter.desktop"
    "krita_svg.desktop"
    "krita_tga.desktop"
    "krita_tiff.desktop"
    "krita_webp.desktop"
    "krita_xcf.desktop"
    # Zathura ships one launcher per backend, all named "Zathura". Keep
    # `org.pwmt.zathura.desktop` as the canonical entry.
    "org.pwmt.zathura-cb.desktop"
    "org.pwmt.zathura-djvu.desktop"
    "org.pwmt.zathura-pdf-mupdf.desktop"
    "org.pwmt.zathura-ps.desktop"
    # VS Code's URL-handler launcher only exists to claim vscode:// links.
    "code-url-handler.desktop"
  ];
  hiddenDesktopEntries = lib.listToAttrs (map (name: {
    name = "applications/${name}";
    value.text = ''
      [Desktop Entry]
      Hidden=true
    '';
  }) hiddenDesktopFiles);
in
{
  xdg.configFile = staticConfigSources // recursiveConfigSources // {
    "nvim/lazy-lock.json".source =
      config.lib.file.mkOutOfStoreSymlink "/home/kevin/repos/dotfiles/config/nvim/lazy-lock.json";

    "hypr/autostart-host.lua" = mkHostConfigFile "autostartHost" "";
    "hypr/input-devices.lua" = mkHostConfigFile "inputDevices" "";
    "hypr/monitors.lua" =
      mkHostConfigFile "monitors"
        "hl.monitor({ output = \"\", mode = \"preferred\", position = \"auto\", scale = \"auto\" })\n";
    "hypr/env-host.lua" = mkHostConfigFile "env" "";

    # Keep the user-level portal config aligned with the NixOS portal selection;
    # this prevents stale user config from forcing Chromium-family file pickers
    # through the KDE backend after Home Manager activation.
    "xdg-desktop-portal/portals.conf".text = ''
      [preferred]
      default = hyprland;gtk
      org.freedesktop.impl.portal.FileChooser = gtk
    '';

    # Snappy Switcher config.ini is generated by desktopctl; only the packaged
    # themes stay symlinked.
    "snappy-switcher/themes".source = "${snappySwitcherPkg}/share/snappy-switcher/themes";

    "wireplumber/wireplumber.conf.d/50-bluetooth.conf".text = ''
      monitor.bluez.properties = {
        bluez5.enable-sbc-xq = true
        bluez5.enable-msbc = true
        bluez5.enable-hw-volume = true
      }
    '';
  };

  xdg.dataFile = hiddenDesktopEntries // {
    # User-local desktop files win over profile entries; keep Bambu's entry
    # aligned with the package so stale AppImage integration metadata cannot
    # shadow the fixed Exec/StartupWMClass values.
    "applications/BambuStudio.desktop" = {
      source = "${bambuStudioPkg}/share/applications/BambuStudio.desktop";
      force = true;
    };
  };

  xdg.desktopEntries.code = {
    name = "Visual Studio Code";
    comment = "Code Editing. Redefined.";
    genericName = "Text Editor";
    icon = "vscode";
    # Lua long string: keeps the Exec line free of nested double quotes.
    exec = ''hyprctl dispatch "hl.dsp.exec_cmd([[code %F]])"'';
    categories = [ "Utility" "TextEditor" "Development" "IDE" ];
    startupNotify = true;
    settings = {
      Keywords = "vscode";
      StartupWMClass = "Code";
      Version = "1.5";
    };
    actions = {
      new-empty-window = {
        name = "New Empty Window";
        icon = "vscode";
        exec = ''hyprctl dispatch "hl.dsp.exec_cmd([[code --new-window %F]])"'';
      };
    };
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "text/html" = "helium.desktop";
      "x-scheme-handler/http" = "helium.desktop";
      "x-scheme-handler/https" = "helium.desktop";
      "application/pdf" = "helium.desktop";
      "inode/directory" = "org.gnome.Nautilus.desktop";
      "image/png" = "imv.desktop";
      "image/jpeg" = "imv.desktop";
      "image/jpg" = "imv.desktop";
      "image/gif" = "imv.desktop";
      "image/webp" = "imv.desktop";
      "image/svg+xml" = "imv.desktop";
      "image/heic" = "org.kde.gwenview.desktop";
      "image/heif" = "org.kde.gwenview.desktop";
      "image/heic-sequence" = "org.kde.gwenview.desktop";
      "image/heif-sequence" = "org.kde.gwenview.desktop";
      "video/mp4" = "org.kde.haruna.desktop";
      "video/x-matroska" = "org.kde.haruna.desktop";
      "video/x-msvideo" = "org.kde.haruna.desktop";
      "video/webm" = "org.kde.haruna.desktop";
      "text/plain" = "org.gnome.gedit.desktop";
      "x-scheme-handler/mailto" = "thunderbird.desktop";
      "x-scheme-handler/terminal" = "Alacritty.desktop";
    };
  };
}
