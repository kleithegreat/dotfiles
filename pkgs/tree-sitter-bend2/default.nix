{ tree-sitter }:

tree-sitter.buildGrammar {
  language = "bend";
  version = "2.0.40";
  src = ./.;
  generate = true;
}
