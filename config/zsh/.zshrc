# ── History ──────────────────────────────────────────────────
HISTSIZE=100000
SAVEHIST=100000
setopt HIST_IGNORE_ALL_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_REDUCE_BLANKS
setopt SHARE_HISTORY
setopt APPEND_HISTORY
setopt INC_APPEND_HISTORY

# ── General Options ──────────────────────────────────────────
setopt AUTO_CD
setopt INTERACTIVE_COMMENTS
setopt NO_BEEP
setopt GLOB_DOTS

# ── Key Mode (must come before custom bindings) ──────────────
bindkey -e

# ── Completion ───────────────────────────────────────────────
autoload -Uz compinit
if [[ -n "$XDG_CACHE_HOME/zsh/zcompdump"(#qN.mh+24) ]]; then
    compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"
else
    compinit -C -d "$XDG_CACHE_HOME/zsh/zcompdump"
fi

zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' group-name ''
zstyle ':completion:*:descriptions' format '%B%d%b'

# ── Plugins (Arch packages) ──────────────────────────────────
source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

# ── Key Bindings (after plugins) ─────────────────────────────
# History substring search — up/down arrows
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down

# Standard keys
bindkey '^[[H'  beginning-of-line
bindkey '^[[F'  end-of-line
bindkey '^[[3~' delete-char
bindkey '^H'    backward-kill-word

# Fish-style path-segment accept (Ctrl+Right)
# Accepts autosuggestion one path segment at a time (/ as word boundary)
_forward_word_path() {
    local WORDCHARS="${WORDCHARS:s#/#}"
    zle forward-word
}
zle -N _forward_word_path
bindkey '^[[1;5C' _forward_word_path

# ── Aliases ──────────────────────────────────────────────────
alias ls="eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions"
alias la="eza --color=always --long --git --icons=always -a"
alias lt="eza --color=always --tree --level=2 --icons=always"
alias ..="cd .."
alias ...="cd ../.."
alias rm="rm -i"
alias mv="mv -i"
alias cp="cp -i"
alias cat="bat --paging=never --style=plain"
alias catn="/usr/bin/cat"
alias grep="grep --color=auto"

# ── Functions ────────────────────────────────────────────────
dps() {
    docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
}

mkcd() {
    mkdir -p "$1" && cd "$1"
}

# ── Tool Integrations ────────────────────────────────────────
eval "$(starship init zsh)"
eval "$(zoxide init zsh --cmd cd)"

# fzf
if command -v fzf &>/dev/null; then
    source <(fzf --zsh 2>/dev/null) || {
        [[ -f /usr/share/fzf/key-bindings.zsh ]] && source /usr/share/fzf/key-bindings.zsh
        [[ -f /usr/share/fzf/completion.zsh ]] && source /usr/share/fzf/completion.zsh
    }
    export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"
    export FZF_DEFAULT_OPTS="--height=40% --layout=reverse --border"
fi

# bat: colorized man pages
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export MANROFFOPT="-c"

# ── GNOME Keyring (SSH agent) ────────────────────────────────
if command -v gnome-keyring-daemon &>/dev/null; then
    eval "$(gnome-keyring-daemon --start --components=pkcs11,secrets,ssh 2>/dev/null)"
    export SSH_AUTH_SOCK
fi

# ── Secrets (API keys, never committed) ──────────────────────
[[ -f "$XDG_STATE_HOME/zsh/secrets.zsh" ]] && source "$XDG_STATE_HOME/zsh/secrets.zsh"

# ── Local overrides (machine-specific, not in dotfiles) ──────
[[ -f "$ZDOTDIR/local.zsh" ]] && source "$ZDOTDIR/local.zsh"