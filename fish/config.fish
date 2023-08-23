set fish_greeting
starship init fish | source

alias xneovide="WINIT_UNIX_BACKEND=x11 neovide"
alias ls="exa -la"
# >>> mamba initialize >>>
# !! Contents within this block are managed by 'mamba init' !!
set -gx MAMBA_EXE "/nix/store/di47ia0jrm39s57d23qz6j4zq94liijk-micromamba-1.2.0/bin/micromamba"
set -gx MAMBA_ROOT_PREFIX "/home/kevin/fish"
$MAMBA_EXE shell hook --shell fish --prefix $MAMBA_ROOT_PREFIX | source
# <<< mamba initialize <<<
function mamba
    /nix/store/di47ia0jrm39s57d23qz6j4zq94liijk-micromamba-1.2.0/bin/micromamba $argv
end
