/**
 * WGSL for CodeMirror 6 as a stream parser (no Lezer grammar in v1): highlighting,
 * nested block comments, `#include` / `// @param` pragmas, comment tokens for
 * toggle-comment. Bracket matching uses CodeMirror's plain-text fallback.
 */

import { HighlightStyle, StreamLanguage, StringStream } from '@codemirror/language';
import { tags as t } from '@lezer/highlight';

const KEYWORDS = new Set([
  'alias', 'break', 'case', 'const', 'const_assert', 'continue', 'continuing', 'default', 'diagnostic',
  'discard', 'else', 'enable', 'fn', 'for', 'if', 'let', 'loop', 'override', 'requires', 'return',
  'struct', 'switch', 'var', 'while',
]);
const TYPE_RE = /^(?:bool|f16|f32|i32|u32|vec[234][fhiu]?|mat[234]x[234][fh]?|array|atomic|ptr|sampler(?:_comparison)?|texture_[a-z0-9_]+|function|private|workgroup|uniform|storage|read|write|read_write)$/;
const NUMBER_RE = /^(?:0[xX][0-9a-fA-F]+[iu]?|(?:\d+\.\d*|\.\d+|\d+)(?:[eE][+-]?\d+)?[fhiu]?)/;
/** The prelude's bindings get their own colour: they are the shader's I/O. */
const BINDINGS = new Set([
  'u', 'u_sampler', 'readTexture', 'writeTexture', 'readDepthTexture', 'non_filtering_sampler',
  'writeDepthTexture', 'dataTextureA', 'dataTextureB', 'dataTextureC', 'extraBuffer', 'comparison_sampler',
  'plasmaBuffer',
]);

interface WgslState {
  /** Nesting depth of an open block comment. */
  comment: number;
  afterDot: boolean;
}

function blockComment(stream: StringStream, state: WgslState): string {
  while (!stream.eol()) {
    if (stream.match('/*')) state.comment += 1;
    else if (stream.match('*/')) {
      state.comment -= 1;
      if (state.comment === 0) break;
    } else stream.next();
  }
  return 'comment';
}

export const wgslLanguage = StreamLanguage.define<WgslState>({
  name: 'wgsl',
  startState: () => ({ comment: 0, afterDot: false }),
  copyState: (s) => ({ ...s }),
  token(stream, state) {
    if (state.comment > 0) return blockComment(stream, state);
    if (stream.eatSpace()) return null;

    if (stream.match(/^\/\/\s*@param\b/)) {
      stream.skipToEnd();
      return 'pragma';
    }
    if (stream.match('//')) {
      stream.skipToEnd();
      return 'comment';
    }
    if (stream.match('/*')) {
      state.comment = 1;
      return blockComment(stream, state);
    }
    if (stream.match(/^#\w+/)) return 'meta';
    if (stream.match(/^"[^"]*"?/)) return 'string';
    if (stream.match(/^@\w+/)) return 'attributeName';
    if (stream.match(NUMBER_RE)) {
      state.afterDot = false;
      return 'number';
    }
    const word = stream.match(/^[A-Za-z_]\w*/) as RegExpMatchArray | null;
    if (word) {
      const w = word[0];
      const wasDot = state.afterDot;
      state.afterDot = false;
      if (wasDot) return 'propertyName';
      if (w === 'true' || w === 'false') return 'bool';
      if (KEYWORDS.has(w)) return 'keyword';
      if (TYPE_RE.test(w)) return 'typeName';
      if (BINDINGS.has(w)) return 'binding';
      if (stream.match(/^\s*\(/, false)) return 'call';
      return 'variableName';
    }
    if (stream.eat('.')) {
      state.afterDot = true;
      return 'punctuation';
    }
    state.afterDot = false;
    if (stream.match(/^[+\-*/%=<>!&|^~]+/)) return 'operator';
    stream.next();
    return null;
  },
  tokenTable: {
    pragma: t.special(t.comment),
    binding: t.special(t.variableName),
    call: t.function(t.variableName),
  },
  languageData: {
    commentTokens: { line: '//', block: { open: '/*', close: '*/' } },
    closeBrackets: { brackets: ['(', '[', '{', '"'] },
  },
});

export const wgslHighlight = HighlightStyle.define([
  { tag: t.comment, color: '#7d8590', fontStyle: 'italic' },
  { tag: t.special(t.comment), color: '#d2a8ff', fontStyle: 'normal' },
  { tag: t.keyword, color: '#ff7b72' },
  { tag: t.typeName, color: '#ffa657' },
  { tag: t.number, color: '#79c0ff' },
  { tag: t.bool, color: '#79c0ff' },
  { tag: t.string, color: '#a5d6ff' },
  { tag: t.meta, color: '#d2a8ff' },
  { tag: t.attributeName, color: '#d2a8ff' },
  { tag: t.function(t.variableName), color: '#e6c07b' },
  { tag: t.special(t.variableName), color: '#7ee787' },
  { tag: t.propertyName, color: '#a5d6ff' },
  { tag: t.operator, color: '#c9d1d9' },
]);
