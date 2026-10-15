# Model-support releases reach nixpkgs master before nixos-unstable. Keep it
# nixpkgs-sourced: a repo-local npm pin broke against the moving builder.
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
