/**
 * wgslSourceMap.ts
 *
 * Expands a draft's `#include`s with the same expander the build and the runtime
 * use (src/wasm/bridge/wgslInclude.ts — one implementation, nothing duplicated),
 * and records where each expanded line came from, so a naga error in the
 * expanded module lands on the user's line and never on a prelude line.
 *
 * The expander is textual and deterministic: a live top-level directive on user
 * line N becomes the marker `// #include-expanded: NAME (from ENTRY:N)` followed
 * by NAME's own expansion. That expansion's length is that of expanding NAME on
 * its own, so the map is rebuilt from the output without touching the expander.
 */

import { expandWgslIncludes, WgslIncludeError, WgslIncludeResolver } from '../wasm/bridge/wgslInclude';

export type LineOrigin =
  | { kind: 'user'; line: number }
  /** Inside an included library: blamed on the user's `#include` line. */
  | { kind: 'library'; name: string; includeLine: number; libraryLine: number };

export interface ExpandedDraft {
  /** The module naga and the GPU see. */
  text: string;
  /** `lineMap[k]` is the origin of expanded line k + 1. */
  lineMap: LineOrigin[];
  /** Every library source the expansion resolved, by name. */
  libraries: ReadonlyMap<string, string>;
}

export type ExpandResult =
  | { ok: true; expanded: ExpandedDraft }
  | { ok: false; line: number; message: string };

/** The entry name used in markers and include error messages. */
export const DRAFT_ENTRY = 'draft.wgsl';

const MARKER_RE = /^\/\/ #include-expanded: (\S+) \(from (.+):(\d+)\)$/;
const DIRECTIVE_RE = /^[ \t]*#include[ \t]+"([^"]+)"[ \t]*$/;
/** `draft.wgsl:12: …` in a WgslIncludeError. */
const ERROR_LINE_RE = new RegExp(`${DRAFT_ENTRY.replace('.', '\\.')}:(\\d+)`);

export async function expandDraft(source: string, resolve: WgslIncludeResolver): Promise<ExpandResult> {
  const libraries = new Map<string, string>();
  const recording: WgslIncludeResolver = async (name) => {
    const text = await resolve(name);
    if (text !== null) libraries.set(name, text);
    return text;
  };

  let text: string;
  try {
    text = await expandWgslIncludes(source, recording, DRAFT_ENTRY);
  } catch (err) {
    const message = err instanceof WgslIncludeError || err instanceof Error ? err.message : String(err);
    const line = Number(ERROR_LINE_RE.exec(message)?.[1] ?? 1);
    return { ok: false, line, message };
  }

  const user = source.split('\n');
  const out = text.split('\n');
  if (text === source) {
    return { ok: true, expanded: { text, lineMap: user.map((_, i) => ({ kind: 'user', line: i + 1 })), libraries } };
  }

  const lengths = new Map<string, number>();
  const libraryLength = async (name: string): Promise<number> => {
    const known = lengths.get(name);
    if (known !== undefined) return known;
    const lib = libraries.get(name) ?? '';
    const n = (await expandWgslIncludes(lib, recording, name)).split('\n').length;
    lengths.set(name, n);
    return n;
  };

  const lineMap: LineOrigin[] = [];
  let k = 0;
  for (let i = 0; i < user.length && k < out.length; i += 1) {
    const line = i + 1;
    const marker = MARKER_RE.exec(out[k] ?? '');
    if (marker && marker[2] === DRAFT_ENTRY && Number(marker[3]) === line && DIRECTIVE_RE.test(user[i] ?? '')) {
      const name = marker[1] ?? '';
      const n = await libraryLength(name);
      lineMap.push({ kind: 'library', name, includeLine: line, libraryLine: 0 });
      for (let j = 1; j <= n; j += 1) lineMap.push({ kind: 'library', name, includeLine: line, libraryLine: j });
      k += 1 + n;
    } else {
      lineMap.push({ kind: 'user', line });
      k += 1;
    }
  }
  // Never leave an expanded line unmapped (a malformed map degrades to the last user line).
  while (lineMap.length < out.length) lineMap.push({ kind: 'user', line: user.length });

  return { ok: true, expanded: { text, lineMap, libraries } };
}

/** Origin of a 1-based expanded line; line 0 (naga could not place it) maps to user line 1. */
export function originOf(expanded: ExpandedDraft, line: number): LineOrigin {
  if (line < 1) return { kind: 'user', line: 1 };
  return expanded.lineMap[line - 1] ?? { kind: 'user', line: Math.max(1, expanded.lineMap.length) };
}
