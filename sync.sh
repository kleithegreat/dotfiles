#!/bin/bash
# sync.sh — Copy dotfiles repo → ~/.config
# Dotfiles repo is source of truth. Run after editing configs in the repo.

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

echo "Syncing dotfiles → ~/.config"
for dir in "${MANAGED_DIRS[@]}"; do
    src="$REPO_DIR/config/$dir"
    dst="$CONFIG_DIR/$dir"
    if [ -d "$src" ]; then
        mkdir -p "$dst"
        rsync -av --delete \
            --exclude '.zsh_history' \
            --exclude '*.png' \
            --exclude '*.jpg' \
            "$src/" "$dst/"
    fi
done
echo "Done."