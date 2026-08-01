#!/bin/sh
# ComfyUI keeps models, custom nodes, inputs, outputs and user settings in one
# writable tree. The application itself lives read-only in the Nix store, so
# point it at a state directory under $XDG_DATA_HOME instead.
#
# The directory skeleton has to exist before startup: main.py lists
# custom_nodes/ during prestartup, and the model loaders never create their own
# folders. The directory list below is expanded at build time from the tree
# upstream ships, so it tracks new model categories across version bumps.
#
# --database-url is not covered by --base-directory: upstream derives it from
# the location of comfy/cli_args.py, which here is the read-only store. Point
# it at the state tree too, otherwise startup fails to open the database.
#
# Both defaults are passed before "$@", so anything the caller supplies wins.
set -eu

base_directory="${COMFYUI_BASE_DIRECTORY:-${XDG_DATA_HOME:-$HOME/.local/share}/comfyui}"
@mkdir@ -p @skeletonDirs@ "$base_directory/user"

exec @python@/bin/python @app@/main.py \
  --base-directory "$base_directory" \
  --database-url "sqlite:///$base_directory/user/comfyui.db" \
  "$@"
