# claude-code moves faster than the nixos-unstable channel, so it is taken from
# a separate nixpkgs input pinned to master.
{ nixpkgs-claude }:

final: _prev:
let
  claudePkgs = import nixpkgs-claude {
    inherit (final.stdenv.hostPlatform) system;
    config.allowUnfreePredicate = pkg: nixpkgs-claude.lib.getName pkg == "claude-code";
  };
in
{
  inherit (claudePkgs) claude-code;
}
