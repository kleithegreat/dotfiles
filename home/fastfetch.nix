{ ... }:

{
  programs.fastfetch = {
    enable = true;
    settings = {
      logo = {
        type = "small";
      };
      display = {
        separator = "  ";
      };
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
}
