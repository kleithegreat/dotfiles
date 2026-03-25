#!/usr/bin/env python3
"""Open an xdg-desktop-portal directory picker and print the chosen path."""
import re, select, subprocess, sys
from urllib.parse import unquote

monitor = subprocess.Popen(
    ["dbus-monitor", "--session",
     "type='signal',interface='org.freedesktop.portal.Request',member='Response'"],
    stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
)

call = subprocess.run(
    ["busctl", "--user", "call",
     "org.freedesktop.portal.Desktop",
     "/org/freedesktop/portal/desktop",
     "org.freedesktop.portal.FileChooser",
     "OpenFile", "ssa{sv}", "", "Select Wallpaper Directory",
     "2", "directory", "b", "true", "modal", "b", "true"],
    capture_output=True, text=True, timeout=5,
)
if call.returncode != 0:
    monitor.kill()
    sys.exit(1)

buf = ""
while True:
    ready, _, _ = select.select([monitor.stdout], [], [], 120)
    if not ready:
        break
    line = monitor.stdout.readline()
    if not line:
        break
    buf += line
    if "file://" in buf:
        m = re.search(r'file://([^\s"]+)', buf)
        if m:
            print(unquote(m.group(1)))
        break
    if "uint32 1" in buf or "uint32 2" in buf:
        break

monitor.kill()
