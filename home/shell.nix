{ config, pkgs, lib, host, ... }:

let
  rebuildSystemFeatures = [
    "benchmark"
    "big-parallel"
    "kvm"
    "nixos-test"
  ] ++ lib.optional pkgs.optimize.enabled pkgs.optimize.hostFeature;
  rebuildFlags =
    lib.optionalString pkgs.optimize.enabled
      "--option system-features ${lib.escapeShellArg (lib.concatStringsSep " " rebuildSystemFeatures)} "
    + "--flake ~/repos/dotfiles#${host.name}";
in

{
  programs.zsh = {
    enable = true;
    package = pkgs.zsh-share-only;
    dotDir = "${config.xdg.configHome}/zsh";

    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 100000;
      save = 100000;
      ignoreAllDups = true;
      ignoreSpace = true;
      append = true;
      extended = true;
      share = true;
    };

    autocd = true;
    enableCompletion = true;
    completionInit = /* bash */ ''
      autoload -Uz compinit
      mkdir --parents "$XDG_CACHE_HOME/zsh"
      # -C trusts an existing dump: delete it if a new completion goes missing.
      compinit -C -d "$XDG_CACHE_HOME/zsh/zcompdump"
    '';
    autosuggestion = {
      enable = true;
      strategy = [ "history" "completion" ];
    };
    syntaxHighlighting.enable = true;

    shellAliases = {
      ls = ''eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions'';
      la = ''eza --color=always --long --git --icons=always --all'';
      lt = ''eza --color=always --tree --level=2 --icons=always'';
      ".." = "cd ..";
      "..." = "cd ../..";
      rm = "rm --interactive";
      mv = "mv --interactive";
      cp = "cp --interactive";
      cat = "bat --paging=never --style=plain";
      catn = "/run/current-system/sw/bin/cat";
      grep = "grep --color=auto";
    };

    plugins = [
      {
        name = "zsh-history-substring-search";
        src = pkgs.zsh-history-substring-search;
        file = "share/zsh-history-substring-search/zsh-history-substring-search.zsh";
      }
    ];

    initContent = /* bash */ ''
      setopt INTERACTIVE_COMMENTS
      setopt NO_BEEP
      setopt GLOB_DOTS
      setopt HIST_REDUCE_BLANKS

      bindkey -e

      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
      zstyle ':completion:*' special-dirs true
      zstyle ':completion:*' group-name '''
      zstyle ':completion:*:descriptions' format '%B%d%b'

      [[ -f "$ZDOTDIR/theme-colors" ]] && source "$ZDOTDIR/theme-colors"
      ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down

      bindkey '^[[H'  beginning-of-line
      bindkey '^[[F'  end-of-line
      bindkey '^[[3~' delete-char
      bindkey '^H'    backward-kill-word

      # Ctrl+Right accepts one path segment, fish-style.
      _forward_word_path() {
          local WORDCHARS="''${WORDCHARS:s#/#}"
          zle forward-word
      }
      zle -N _forward_word_path
      bindkey '^[[1;5C' _forward_word_path

      dps() {
          podman ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | awk '
              NR==1 { printf "\033[1;34m%s\033[0m\n", $0; next }
              /Up/                       { c="\033[32m" }
              /Exited/                   { c="\033[31m" }
              /Created|Paused|Restarting/ { c="\033[33m" }
              { printf "%s%s\033[0m\n", c, $0; c="" }
          '
      }

      mkcd() {
          mkdir --parents "$1" && cd "$1"
      }

      # Mutes Hyprland's config watcher during activation, then refreshes Vicinae
      # and Quickshell; see docs/nix.md. Non-empty $watcher: activating, Hyprland reachable.
      # Also drops desktopctl's dev-only cargo cache, which Cargo never prunes.
      nrs() {
          local action=switch
          case "$1" in
              switch|boot|test|build|dry-build|dry-activate) action=$1; shift ;;
          esac

          local watcher shell_before
          shell_before=$(readlink "''${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" 2>/dev/null)
          if [[ $action == switch || $action == test ]]; then
              # Reported as `bool:`, not `int:`; the wrong prefix leaves it empty.
              watcher=$(hyprctl getoption misc:disable_autoreload 2>/dev/null | awk '/^bool:/ { print $2 }')
          fi

          if [[ -n $watcher ]]; then
              hyprctl eval 'hl.config({ misc = { disable_autoreload = true } })' >/dev/null
              trap "hyprctl eval 'hl.config({ misc = { disable_autoreload = $watcher } })' >/dev/null 2>&1" EXIT INT TERM
          fi

          rm --recursive --force ~/repos/dotfiles/desktopctl/target

          sudo nixos-rebuild "$action" ${rebuildFlags} "$@"
          local rc=$?

          if [[ -n $watcher ]]; then
              trap - EXIT INT TERM
              hyprctl eval "hl.config({ misc = { disable_autoreload = $watcher } })" >/dev/null
              if (( rc == 0 )); then
                  hyprctl dispatch 'hl.dsp.exec_cmd("vicinae server --replace")' >/dev/null
                  if [[ $(readlink "''${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/shell.qml" 2>/dev/null) != "$shell_before" ]]; then
                      hyprctl dispatch 'hl.dsp.exec_cmd("pkill quickshell || true; sleep 0.3; desktopctl launch-quickshell")' >/dev/null
                  fi
              fi
          fi

          return $rc
      }

      export MANPAGER="sh -c 'col --no-backspaces --spaces | bat --language=man --plain'"
      export MANROFFOPT="-c"

      # gcr-ssh-agent.socket
      export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh"

      [[ -f "$XDG_STATE_HOME/zsh/secrets.zsh" ]] && source "$XDG_STATE_HOME/zsh/secrets.zsh"

      [[ -f "$ZDOTDIR/local.zsh" ]] && source "$ZDOTDIR/local.zsh"
    '';
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "helium";
    PAGER = "less";

    GOPATH = "${config.xdg.dataHome}/go";

    PYTHON_HISTORY = "${config.xdg.stateHome}/python/history";
    NODE_REPL_HISTORY = "${config.xdg.stateHome}/node/history";
    PSQL_HISTORY = "${config.xdg.stateHome}/psql/history";
    MYSQL_HISTFILE = "${config.xdg.stateHome}/mariadb/history";
    LESSHISTFILE = "${config.xdg.stateHome}/less/history";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.cargo/bin"
  ];

  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [ "--cmd" "cd" ];
  };

  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidget.command = "fd --type f --hidden --follow --exclude .git";
    changeDirWidget.command = "fd --type d --hidden --follow --exclude .git";
    defaultOptions = [ "--height=40%" "--layout=reverse" "--border" ];
  };

  programs.eza = {
    enable = true;
    enableZshIntegration = false;
    icons = "auto";
    git = true;
  };

  programs.bat.enable = true;

  programs.fastfetch = {
    enable = true;
    settings = {
      logo.type = "small";
      display.separator = "  ";
      modules = [
        "os"
        "host"
        "kernel"
        "uptime"
        "packages"
        "shell"
        "wm"
        "terminal"
        "cpu"
        "gpu"
        "memory"
        "disk"
      ];
    };
  };

  programs.git = {
    enable = true;
    package = pkgs.gitFull;
    settings = {
      user.name = "Kevin";
      user.email = "kevvinlei89@gmail.com";
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
    };
  };
}
