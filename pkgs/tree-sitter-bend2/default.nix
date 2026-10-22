{ tree-sitter }:

tree-sitter.buildGrammar {
  language = "bend";
  version = "2.0.38";
  src = ./.;
  generate = true;
}
