set fish_greeting
set -q GHCUP_INSTALL_BASE_PREFIX[1]; or set GHCUP_INSTALL_BASE_PREFIX $HOME ; set -gx PATH $HOME/.cabal/bin /home/kevin/.ghcup/bin $PATH # ghcup-env

starship init fish | source
zoxide init fish | source
thefuck --alias | source

alias ls="eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions"
# alias cat="bat"
alias cd="z"
alias skibidi="psql -h csce-315-db.engr.tamu.edu -U team_2b -d team_2b_db \ paras"

# Created by `pipx` on 2024-05-28 18:58:49
set PATH $PATH /home/kevin/.local/bin

set -gx PATH /opt/cuda/bin $PATH
set -gx LD_LIBRARY_PATH /opt/cuda/lib64 $LD_LIBRARY_PATH

# pnpm
set -gx PNPM_HOME "/home/kevin/.local/share/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end


# BEGIN opam configuration
# This is useful if you're using opam as it adds:
#   - the correct directories to the PATH
#   - auto-completion for the opam binary
# This section can be safely removed at any time if needed.
test -r '/home/kevin/.opam/opam-init/init.fish' && source '/home/kevin/.opam/opam-init/init.fish' > /dev/null 2> /dev/null; or true
# END opam configuration

# Nix
if test -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
    fenv source '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
end

# Add nix binaries to PATH
set -gx PATH $PATH /nix/var/nix/profiles/default/bin
set -x NIX_CONFIG "experimental-features = nix-command flakes"