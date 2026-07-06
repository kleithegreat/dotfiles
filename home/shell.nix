{ config, pkgs, lib, host, enableNativeOptimizations, ... }:

let
  zshShareOnly = pkgs.runCommand "zsh-share-only" {} ''
    mkdir -p "$out/share"
    ln -s ${pkgs.zsh}/share/zsh "$out/share/zsh"
  '';
  rebuildSystemFeatures = [
    "benchmark"
    "big-parallel"
    "kvm"
    "nixos-test"
  ] ++ lib.optionals enableNativeOptimizations [ "native-optimized-${host.name}" ];
  nixosRebuildCommand =
    "sudo nixos-rebuild switch"
    + lib.optionalString enableNativeOptimizations
      " --option system-features ${lib.escapeShellArg (lib.concatStringsSep " " rebuildSystemFeatures)}"
    + " --flake ~/repos/dotfiles#${host.name}";
in

{
  # ── Zsh ──────────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    package = zshShareOnly;
    dotDir = "${config.xdg.configHome}/zsh";

    history = {
      path = "${config.xdg.stateHome}/zsh/history";
      size = 100000;
      save = 100000;
      ignoreAllDups = true;
      ignoreSpace = true;
      extended = true;
      share = true;
    };

    autocd = true;
    enableCompletion = true;
    completionInit = ''
      autoload -Uz compinit
      mkdir -p "$XDG_CACHE_HOME/zsh"
      compinit -C -d "$XDG_CACHE_HOME/zsh/zcompdump"
    '';
    autosuggestion = {
      enable = true;
      strategy = [ "history" "completion" ];
    };
    syntaxHighlighting.enable = true;

    shellAliases = {
      ls = ''eza --color=always --long --git --no-filesize --icons=always --no-time --no-user --no-permissions'';
      la = ''eza --color=always --long --git --icons=always -a'';
      lt = ''eza --color=always --tree --level=2 --icons=always'';
      ".." = "cd ..";
      "..." = "cd ../..";
      rm = "rm -i";
      mv = "mv -i";
      cp = "cp -i";
      cat = "bat --paging=never --style=plain";
      catn = "/run/current-system/sw/bin/cat";
      grep = "grep --color=auto";
      nrs = "hyprctl keyword misc:disable_autoreload true && ${nixosRebuildCommand}; rc=$?; hyprctl keyword misc:disable_autoreload false; if [ $rc -eq 0 ]; then hyprctl dispatch exec 'vicinae server --replace' >/dev/null; fi; (exit $rc)";
    };

    plugins = [
      {
        name = "zsh-history-substring-search";
        src = pkgs.zsh-history-substring-search;
        file = "share/zsh-history-substring-search/zsh-history-substring-search.zsh";
      }
      {
        name = "zsh-per-directory-history";
        src = pkgs.fetchFromGitHub {
          owner = "jimhester";
          repo = "per-directory-history";
          rev = "95f06973e9f2ff0ff75f3cebd0a2ee5485e27834";
          sha256 = "sha256-EV9QPBndwAWzdOcghDXrIIgP0oagVMOTyXzoyt8tXRo=";
        };
        file = "per-directory-history.zsh";
      }
    ];

    initContent = ''
      # ── Options ──────────────────────────────────────────────
      setopt INTERACTIVE_COMMENTS
      setopt NO_BEEP
      setopt GLOB_DOTS
      setopt HIST_REDUCE_BLANKS
      setopt APPEND_HISTORY
      setopt INC_APPEND_HISTORY

      # ── Per-directory history ──────────────────────────────────
      # Ctrl+G toggles between directory-local and global history
      PER_DIRECTORY_HISTORY_TOGGLE='^G'
      HISTORY_START_WITH_GLOBAL=false

      # ── Emacs keybindings ────────────────────────────────────
      bindkey -e

      # ── Completion styles ────────────────────────────────────
      zstyle ':completion:*' menu select
      zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'
      zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"
      zstyle ':completion:*' special-dirs true
      zstyle ':completion:*' group-name '''
      zstyle ':completion:*:descriptions' format '%B%d%b'

      # ── Autosuggestion config ────────────────────────────────
      [[ -f "$ZDOTDIR/theme-colors" ]] && source "$ZDOTDIR/theme-colors"
      ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

      # ── Key bindings ─────────────────────────────────────────
      # History substring search
      bindkey '^[[A' history-substring-search-up
      bindkey '^[[B' history-substring-search-down

      # Standard keys
      bindkey '^[[H'  beginning-of-line
      bindkey '^[[F'  end-of-line
      bindkey '^[[3~' delete-char
      bindkey '^H'    backward-kill-word

      # Fish-style path-segment accept (Ctrl+Right)
      _forward_word_path() {
          local WORDCHARS="''${WORDCHARS:s#/#}"
          zle forward-word
      }
      zle -N _forward_word_path
      bindkey '^[[1;5C' _forward_word_path

      # ── Functions ────────────────────────────────────────────
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
          mkdir -p "$1" && cd "$1"
      }

      # ── bat as manpager ──────────────────────────────────────
      export MANPAGER="sh -c 'col -bx | bat -l man -p'"
      export MANROFFOPT="-c"

      # ── SSH agent (GCR socket, managed by gcr-ssh-agent.socket) ──
      export SSH_AUTH_SOCK="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/gcr/ssh"

      # ── Secrets (never committed) ───────────────────────────
      [[ -f "$XDG_STATE_HOME/zsh/secrets.zsh" ]] && source "$XDG_STATE_HOME/zsh/secrets.zsh"

      # ── Local overrides (machine-specific) ──────────────────
      [[ -f "$ZDOTDIR/local.zsh" ]] && source "$ZDOTDIR/local.zsh"
    '';
  };

  # ── Session variables (.zshenv equivalent) ───────────────────
  home.sessionVariables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    BROWSER = "helium";
    PAGER = "less";

    # XDG path redirects
    GOPATH = "${config.xdg.dataHome}/go";

    # XDG history redirects
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

  # ── Starship ─────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── Zoxide (replaces cd) ─────────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    options = [ "--cmd" "cd" ];
  };

  # ── fzf ──────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --hidden --follow --exclude .git";
    fileWidget.command = "fd --type f --hidden --follow --exclude .git";
    changeDirWidget.command = "fd --type d --hidden --follow --exclude .git";
    defaultOptions = [ "--height=40%" "--layout=reverse" "--border" ];
  };

  # ── eza ─────────────────────────────────────────────────────
  programs.eza = {
    enable = true;
    enableZshIntegration = false;
    icons = "auto";
    git = true;
  };

  # ── bat ──────────────────────────────────────────────────────
  programs.bat.enable = true;

  # ── Git ──────────────────────────────────────────────────────
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
