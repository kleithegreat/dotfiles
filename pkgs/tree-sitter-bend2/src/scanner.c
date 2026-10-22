#include "tree_sitter/array.h"
#include "tree_sitter/parser.h"

#include <string.h>
#include <wctype.h>

enum TokenType {
  CALL_OPEN,
  INDEX_OPEN,
  TYPE_CLOSE,
  CONSTRUCTOR_OPEN,
  BLOCK_START,
  BLOCK_END,
  ERROR_SENTINEL,
};

// The columns of the open match and do blocks, innermost last.
typedef Array(uint16_t) Blocks;

void *tree_sitter_bend_external_scanner_create(void) {
  Blocks *blocks = ts_calloc(1, sizeof(Blocks));
  array_init(blocks);
  return blocks;
}

void tree_sitter_bend_external_scanner_destroy(void *payload) {
  Blocks *blocks = payload;
  array_delete(blocks);
  ts_free(blocks);
}

unsigned tree_sitter_bend_external_scanner_serialize(void *payload, char *buffer) {
  Blocks *blocks = payload;
  unsigned size = blocks->size * sizeof(uint16_t);
  if (size > TREE_SITTER_SERIALIZATION_BUFFER_SIZE) {
    size = TREE_SITTER_SERIALIZATION_BUFFER_SIZE / sizeof(uint16_t) * sizeof(uint16_t);
  }
  memcpy(buffer, blocks->contents, size);
  return size;
}

void tree_sitter_bend_external_scanner_deserialize(void *payload, const char *buffer, unsigned length) {
  Blocks *blocks = payload;
  array_clear(blocks);
  array_reserve(blocks, length / sizeof(uint16_t));
  memcpy(blocks->contents, buffer, length);
  blocks->size = length / sizeof(uint16_t);
}

static bool emit(TSLexer *lexer, enum TokenType type) {
  lexer->advance(lexer, false);
  lexer->mark_end(lexer);
  lexer->result_symbol = type;
  return true;
}

bool tree_sitter_bend_external_scanner_scan(void *payload, TSLexer *lexer, const bool *valid) {
  Blocks *blocks = payload;
  if (valid[ERROR_SENTINEL]) {
    return false;
  }

  // The scanner runs before whitespace is skipped, so these are glued.
  if (valid[TYPE_CLOSE] && lexer->lookahead == '>') {
    return emit(lexer, TYPE_CLOSE);
  }
  if (valid[CONSTRUCTOR_OPEN] && lexer->lookahead == '{') {
    return emit(lexer, CONSTRUCTOR_OPEN);
  }

  bool newline = false;
  while (iswspace(lexer->lookahead)) {
    newline |= lexer->lookahead == '\n';
    lexer->advance(lexer, true);
  }
  if (!newline && valid[CALL_OPEN] && lexer->lookahead == '(') {
    return emit(lexer, CALL_OPEN);
  }
  if (!newline && valid[INDEX_OPEN] && lexer->lookahead == '[') {
    return emit(lexer, INDEX_OPEN);
  }
  if (!valid[BLOCK_START] && !valid[BLOCK_END]) {
    return false;
  }

  lexer->mark_end(lexer);
  while (!lexer->eof(lexer) && (iswspace(lexer->lookahead) || lexer->lookahead == '#')) {
    if (lexer->lookahead == '#') {
      while (!lexer->eof(lexer) && lexer->lookahead != '\n') {
        lexer->advance(lexer, false);
      }
    } else {
      lexer->advance(lexer, false);
    }
  }
  uint16_t column = lexer->get_column(lexer);
  uint16_t enclosing = blocks->size > 0 ? *array_back(blocks) : 0;
  int32_t next = lexer->lookahead;
  bool closed = lexer->eof(lexer) || next == ')' || next == ']' || next == '}' || next == ',';

  // A block's items sit right of the enclosing block's, or the block is empty.
  if (valid[BLOCK_START] && !closed && column > enclosing) {
    array_push(blocks, column);
    lexer->result_symbol = BLOCK_START;
    return true;
  }
  if (valid[BLOCK_END] && blocks->size > 0 && (closed || column < enclosing)) {
    array_pop(blocks);
    lexer->result_symbol = BLOCK_END;
    return true;
  }
  return false;
}
