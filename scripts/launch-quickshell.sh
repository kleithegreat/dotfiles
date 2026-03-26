#!/usr/bin/env sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cursor_conf="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/cursor.conf"

unset HYPRCURSOR_THEME

if [ -f "$cursor_conf" ]; then
    while IFS= read -r line; do
        case "$line" in
            "env = XCURSOR_THEME,"*)
                export XCURSOR_THEME=${line#env = XCURSOR_THEME,}
                ;;
            "env = XCURSOR_SIZE,"*)
                export XCURSOR_SIZE=${line#env = XCURSOR_SIZE,}
                ;;
            "env = HYPRCURSOR_THEME,"*)
                export HYPRCURSOR_THEME=${line#env = HYPRCURSOR_THEME,}
                ;;
        esac
    done < "$cursor_conf"
fi

if [ "${1:-}" = "--print-env" ]; then
    printf '%s|%s|%s\n' "${XCURSOR_THEME:-}" "${HYPRCURSOR_THEME:-}" "${XCURSOR_SIZE:-}"
    exit 0
fi

exec quickshell -p "$repo_dir/config/quickshell"
