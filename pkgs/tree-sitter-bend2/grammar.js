/**
 * @file Bend 2, after the reference parser in bendlang/bend's bend2/bend.ts
 */

const PREC = {
  body: -1,
  arrow: 0,
  pair: 1,
  or: 2,
  and: 3,
  compare: 4,
  cons: 5,
  bit_or: 6,
  bit_xor: 7,
  bit_and: 8,
  shift: 9,
  add: 10,
  multiply: 11,
  postfix: 12,
};

const INFIX = [
  ['->', PREC.arrow, prec.right],
  ['&', PREC.pair, prec.right],
  ['|', PREC.pair, prec.right],
  ['||', PREC.or, prec.left],
  ['&&', PREC.and, prec.left],
  ['<', PREC.compare, prec.left],
  ['<=', PREC.compare, prec.left],
  ['>', PREC.compare, prec.left],
  ['>=', PREC.compare, prec.left],
  ['<>', PREC.cons, prec.right],
  ['++', PREC.cons, prec.right],
  ['<&>', PREC.cons, prec.right],
  ['.|.', PREC.bit_or, prec.left],
  ['.^.', PREC.bit_xor, prec.left],
  ['.&.', PREC.bit_and, prec.left],
  ['<<', PREC.shift, prec.left],
  ['>>', PREC.shift, prec.left],
  ['+', PREC.add, prec.left],
  ['-', PREC.add, prec.left],
  ['*', PREC.multiply, prec.left],
  ['/', PREC.multiply, prec.left],
  // A glued % heads a rewrite.
  [alias(token(/%\s/), '%'), PREC.multiply, prec.left],
];

const NAME = /[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*/;

// Bend separates list items with optional commas.
const items = (rule) => repeat(seq(rule, optional(',')));

module.exports = grammar({
  name: 'bend',

  externals: $ => [
    $._call_open,
    $._index_open,
    $._type_close,
    $._constructor_open,
    $._block_start,
    $._block_end,
    $._error_sentinel,
  ],

  extras: $ => [/\s/, $.comment],

  word: $ => $.name,

  // Bend's parser settles each of these by layout or by reading past it.
  conflicts: $ => [
    [$._statement, $._primary],
    [$.let],
    [$._binder, $._primary],
  ],

  rules: {
    source_file: $ => seq(repeat($.import), repeat(choice($.def, $.type, $.law))),

    comment: _ => token(seq('#', /.*/)),

    import: $ => seq(
      'import',
      field('path', $.path),
      optional(seq('as', field('alias', $.name))),
    ),

    path: _ => /[A-Za-z0-9_.\/@-]+/,

    def: $ => seq(
      optional($.unsafe),
      'def',
      field('name', $.name),
      optional('?'),
      '(',
      items($.parameter),
      ')',
      optional(seq('->', field('type', $._term))),
      ':',
      field('body', choice($.body, repeat1($.foreign))),
    ),

    unsafe: _ => seq('@', 'unsafe'),

    foreign: $ => seq('import', $.string),

    parameter: $ => seq(
      optional('~'),
      field('name', $._binder),
      optional(seq(':', field('type', $._term))),
    ),

    type: $ => seq(
      'type',
      field('name', $.name),
      optional(seq('<', items($.parameter), alias($._type_close, '>'))),
      'is',
      field('kind', $._term),
      ':',
      repeat($.constructor),
    ),

    constructor: $ => seq(field('name', $.name), '{', items($.parameter), '}'),

    law: $ => seq(
      'law',
      field('name', $.name),
      ':',
      repeat($.clause),
      field('body', $.body),
    ),

    clause: $ => seq(
      choice(seq('for', optional('~')), 'exs'),
      field('name', $._binder),
      ':',
      field('type', $._term),
      optional(seq('where', field('witness', $._term))),
    ),

    body: $ => prec.right(PREC.body, seq(repeat($._statement), choice($.match, $._term))),

    _statement: $ => choice($.let, seq($.index, optional(';'))),

    let: $ => seq(
      choice(
        seq(field('pattern', $._term), '=', field('value', $._term)),
        seq(
          field('pattern', $._binder),
          ':',
          field('type', $._term),
          '=',
          field('value', $._term),
        ),
        seq(
          field('pattern', $._binder),
          repeat1(field('pattern', $._binder)),
          '=',
          field('value', $._term),
          repeat1(field('value', $._term)),
        ),
      ),
      optional(';'),
    ),

    match: $ => seq(
      'match',
      items(field('subject', $._term)),
      ':',
      optional(seq($._block_start, repeat1($.case), $._block_end)),
    ),

    case: $ => seq(
      'case',
      items(field('pattern', $._term)),
      ':',
      field('body', $.body),
    ),

    _term: $ => choice(
      $.binary,
      $.lambda,
      $.forall,
      $.exists,
      $.rewrite,
      $._primary,
    ),

    _primary: $ => choice(
      $.name,
      $.quantified_name,
      $.hole,
      $.number,
      $.successor,
      $.char,
      $.string,
      $.quantity,
      $.universe,
      $.kind,
      $.call,
      $.index,
      $.constructor_term,
      $.type_application,
      $.annotation,
      $.reflexivity,
      $.lambda_match,
      $.parens,
      $.list,
      $.array,
      $.do,
    ),

    binary: $ => choice(...INFIX.map(([operator, precedence, associate]) =>
      associate(precedence, seq(
        field('left', $._term),
        field('operator', operator),
        field('right', $._term),
      )))),

    lambda: $ => prec.right(PREC.body, seq(
      choice(
        field('parameter', $._binder),
        seq('(', field('parameter', $._binder), ':', field('type', $._term), ')'),
      ),
      '=>',
      field('body', $.body),
    )),

    forall: $ => prec.right(PREC.arrow, seq(
      '@',
      field('name', $._binder),
      ':',
      field('domain', $._term),
      '->',
      field('codomain', $._term),
    )),

    exists: $ => prec.right(PREC.arrow, seq(
      '&',
      field('name', $.name),
      ':',
      field('domain', $._term),
      '->',
      field('codomain', $._term),
    )),

    rewrite: $ => prec.right(PREC.body, seq(
      '%',
      optional(seq(field('name', $.name), '@')),
      field('equation', $._term),
      ':',
      field('motive', $._term),
      optional(';'),
      field('body', $.body),
    )),

    call: $ => prec(PREC.postfix, seq(
      field('function', $._primary),
      optional('!'),
      alias($._call_open, '('),
      items(seq(optional('~'), field('argument', $._term))),
      ')',
    )),

    index: $ => prec.right(PREC.postfix, seq(
      field('array', $._primary),
      alias($._index_open, '['),
      field('index', $._term),
      ']',
      optional(seq('<-', field('value', $._term))),
    )),

    constructor_term: $ => prec(PREC.postfix, seq(
      field('name', $.name),
      alias($._constructor_open, '{'),
      items(field('field', $._term)),
      '}',
    )),

    type_application: $ => prec(PREC.postfix, seq(
      field('name', $._binder),
      '<',
      items(field('argument', $._term)),
      alias($._type_close, '>'),
    )),

    annotation: $ => seq(
      '{',
      field('value', $._term),
      optional(seq(choice('==', '!='), field('other', $._term))),
      ':',
      field('type', $._term),
      '}',
    ),

    reflexivity: _ => seq('{', '==', '}'),

    lambda_match: $ => seq(
      '\\',
      '{',
      repeat($.arm),
      optional(seq(field('default', $._term), optional(';'))),
      '}',
    ),

    arm: $ => seq(field('constructor', $.name), ':', field('body', $._term), optional(';')),

    parens: $ => seq(
      '(',
      $.body,
      repeat(seq(',', $.body)),
      optional(seq(':', field('type', $._term))),
      ')',
    ),

    list: $ => seq('[', items($._term), ']'),

    array: $ => seq(
      '[',
      field('value', $._term),
      ':',
      field('type', $._primary),
      choice('*', '^'),
      field('size', $._term),
      ']',
    ),

    do: $ => seq(
      'do',
      field('monad', $.name),
      '<',
      items(field('argument', $._term)),
      alias($._type_close, '>'),
      ':',
      $._block_start,
      repeat1(seq(choice($.return, $.bind, $._term), optional(';'))),
      $._block_end,
    ),

    return: $ => seq('return', $._term),

    bind: $ => choice(
      seq(
        field('name', $._binder),
        ':',
        field('type', $._term),
        choice('<-', '='),
        field('value', $._term),
      ),
      seq(field('type', $._term), '<-', field('value', $._term)),
    ),

    universe: _ => choice('Type', 'Data', 'Quant'),

    kind: $ => seq('Kind', '(', $._term, ')'),

    quantity: _ => /&[012]/,

    hole: _ => /\?[A-Za-z_][A-Za-z0-9_]*/,

    number: _ => /\d+(n|\.\d+([eE][+-]?\d+)?)?/,

    // 3n+p is Succ{Succ{Succ{p}}}; the + is glued to the n.
    successor: $ => seq(alias(/\d+n\+/, $.number), field('predecessor', $._primary)),

    char: _ => token(seq("'", choice(/[^'\\]/, /\\u\{[0-9A-Fa-f]+\}/, /\\./), "'")),

    string: $ => seq('"', repeat(choice($.string_content, $.escape)), '"'),

    string_content: _ => token.immediate(prec(1, /[^"\\]+/)),

    escape: _ => token.immediate(seq('\\', choice(/u\{[0-9A-Fa-f]+\}/, /./))),

    _binder: $ => choice($.name, $.quantified_name),

    // A + or - glued to a name is never an operator: -x is erased, +x reusable.
    quantified_name: _ => token(seq(/[+-]/, NAME)),

    name: _ => NAME,
  },
});
