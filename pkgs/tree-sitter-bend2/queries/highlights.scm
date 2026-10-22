; Later patterns take precedence, so name heuristics come first.

(name) @variable

(quantified_name) @variable

((name) @type
  (#match? @type "^[A-Z][A-Za-z0-9_]*$"))

((name) @type
  (#match? @type "\\.[A-Z][A-Za-z0-9_]*$"))

((name) @function
  (#match? @function "\\.[a-z_][A-Za-z0-9_]*$"))

(def
  name: (name) @function)

(law
  name: (name) @function)

(call
  function: (name) @function.call)

(type
  name: (name) @type.definition)

(type_application
  name: (_) @type)

(do
  monad: (name) @type)

(constructor
  name: (name) @constructor)

(constructor_term
  name: (name) @constructor)

(arm
  constructor: (name) @constructor)

(parameter
  name: (_) @variable.parameter)

(lambda
  parameter: (_) @variable.parameter)

(forall
  name: (_) @variable.parameter)

(exists
  name: (_) @variable.parameter)

(clause
  name: (_) @variable.parameter)

(rewrite
  name: (name) @variable.parameter)

(import
  path: (path) @string.special.path)

(import
  alias: (name) @module)

[
  (universe)
  "Kind"
] @type.builtin

(quantity) @constant.builtin

(hole) @label

(number) @number

((number) @number.float
  (#match? @number.float "\\."))

(char) @character

(string) @string

(escape) @string.escape

(comment) @comment @spell

(unsafe) @attribute

[
  "def"
  "type"
  "law"
  "is"
  "for"
  "exs"
  "where"
] @keyword

[
  "do"
  "return"
] @keyword

[
  "match"
  "case"
] @keyword.conditional

[
  "import"
  "as"
] @keyword.import

[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
  "<"
  ">"
] @punctuation.bracket

[
  ","
  ";"
  ":"
] @punctuation.delimiter

[
  "="
  "=>"
  "<-"
  "->"
  "=="
  "!="
  "!"
  "?"
  "~"
  "%"
  "\\"
  "@"
  "&"
  "*"
  "^"
] @operator

(binary
  operator: _ @operator)
