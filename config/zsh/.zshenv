# XDG Base Directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"

# Zsh XDG compliance
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export HISTFILE="$XDG_STATE_HOME/zsh/history"

# History file redirects (XDG compliance)
export PYTHON_HISTORY="$XDG_STATE_HOME/python/history"
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node/history"
export PSQL_HISTORY="$XDG_STATE_HOME/psql/history"
export MYSQL_HISTFILE="$XDG_STATE_HOME/mariadb/history"
export LESSHISTFILE="$XDG_STATE_HOME/less/history"

# Default programs
export EDITOR="nvim"
export VISUAL="nvim"
export BROWSER="chromium"
export PAGER="less"

# PATH
typeset -U path  # deduplicate
path=(
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
    $path
)

# Nix (if installed)
[[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]] && source "$HOME/.nix-profile/etc/profile.d/nix.sh"
[[ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]] && source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"