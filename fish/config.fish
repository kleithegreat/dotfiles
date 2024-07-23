set fish_greeting
set -q GHCUP_INSTALL_BASE_PREFIX[1]; or set GHCUP_INSTALL_BASE_PREFIX $HOME ; set -gx PATH $HOME/.cabal/bin /home/kevin/.ghcup/bin $PATH # ghcup-env

starship init fish | source
zoxide init fish | source
thefuck --alias | source

alias ls="eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions"
alias cat="bat"
alias cd="z"

# Created by `pipx` on 2024-05-28 18:58:49
set PATH $PATH /home/kevin/.local/bin

set -gx PATH /opt/cuda/bin $PATH
set -gx LD_LIBRARY_PATH /opt/cuda/lib64 $LD_LIBRARY_PATH
