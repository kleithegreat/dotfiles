#!/bin/sh
# --base-directory neither creates the skeleton ComfyUI expects (the list is
# taken from upstream's tree at build time) nor moves the database out of the
# read-only store. Caller arguments come last and win.
set -eu

base_directory="${COMFYUI_BASE_DIRECTORY:-${XDG_DATA_HOME:-$HOME/.local/share}/comfyui}"
@mkdir@ --parents @skeletonDirs@ "$base_directory/user"

exec @python@/bin/python @app@/main.py \
  --base-directory "$base_directory" \
  --database-url "sqlite:///$base_directory/user/comfyui.db" \
  "$@"
