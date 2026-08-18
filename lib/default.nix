# Extends nixpkgs `lib` with every other file in this directory, so helpers are
# reachable as `lib.<namespace>.<name>` from any module without being threaded
# through as arguments. Each sibling file takes `{ self }` -- the fully extended
# lib -- and returns the attrset to merge in.
lib:
let
  inherit (lib.attrsets) recursiveUpdate;
  inherit (lib.filesystem) listFilesRecursive;
  inherit (lib.lists) filter foldl';
  inherit (lib.strings) hasSuffix;
in
lib.extend (
  final: prev:
  listFilesRecursive ./.
  |> filter (file: file != ./default.nix && hasSuffix ".nix" file)
  |> map (file: import file { self = final; })
  |> foldl' recursiveUpdate prev
)
