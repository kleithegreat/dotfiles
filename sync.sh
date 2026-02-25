#!/bin/bash
# sync.sh — Copy dotfiles repo → ~/.config
# Dotfiles repo is source of truth.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.config"

MANAGED_DIRS=(
    hypr
    quickshell
    alacritty
    ghostty
    zsh
    starship
    zathura
    tmux
    vicinae
    git
    nvim
)

# Files to exclude from sync
EXCLUDES=(
    --exclude '.zsh_history'
    --exclude '*.png'
    --exclude '*.jpg'
)

echo "Syncing dotfiles → ~/.config"
for dir in "${MANAGED_DIRS[@]}"; do
    src="$REPO_DIR/config/$dir"
    dst="$CONFIG_DIR/$dir"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        rsync -av --delete "${EXCLUDES[@]}" "$src/" "$dst/"
    fi
done

# Special cases: flat files in .config root
[ -f "$REPO_DIR/config/starship/starship.toml" ] && \
    cp "$REPO_DIR/config/starship/starship.toml" "$CONFIG_DIR/starship.toml"

echo "Done."