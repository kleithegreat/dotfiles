{
  coreutils,
  libnotify,
  systemd,
  util-linux,
  writeShellApplication,
}:

writeShellApplication {
  name = "kernel-oom-notifier";
  runtimeInputs = [ coreutils libnotify systemd util-linux ];
  text = /* bash */ ''
    notify_user=kevin
    notify_uid="$(id -u "$notify_user")"

    journalctl --dmesg --follow --output=cat --since=now | while IFS= read -r line; do
      summary=""

      case "$line" in
        *"Killed process "*)
          rest="''${line#*Killed process }"
          pid="''${rest%% *}"
          comm="process"

          case "$rest" in
            *"("*")"*)
              comm="''${rest#*(}"
              comm="''${comm%%)*}"
              ;;
          esac

          summary="Kernel OOM killed $comm"
          if [ -n "$pid" ]; then
            summary="$summary (pid $pid)"
          fi
          ;;
        *"Out of memory:"*)
          summary="Kernel OOM event"
          ;;
        *)
          continue
          ;;
      esac

      if [ -S "/run/user/$notify_uid/bus" ]; then
        runuser -u "$notify_user" -- env \
          XDG_RUNTIME_DIR="/run/user/$notify_uid" \
          DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$notify_uid/bus" \
          notify-send \
            --app-name="kernel-oom" \
            --urgency=critical \
            --expire-time=15000 \
            "$summary" \
            "$line" || true
      fi
    done
  '';
}
