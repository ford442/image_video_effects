/**
 * wgslDiagnostics.ts
 *
 * Draft source → editor diagnostics: expand `#include` (wgslSourceMap.ts) → naga
 * validate (utils/nagaWasm.ts, the committed lazy artifact) → map naga's line back
 * through the include expansion. Also checks the `// @param` header and that the
 * module has the `@compute fn main` the renderer dispatches.
 *
 * `createDiagnosticScheduler` debounces keystrokes (150 ms) and drops stale results,
 * so the editor shows the diagnostics of the latest text within ~150 ms + one naga
 * pass (a few ms on a typical shader) of the last keystroke.
 */

import type { NagaDiagnostic, NagaReflection } from '../utils/nagaWasm';
import type { WgslIncludeResolver } from '../wasm/bridge/wgslInclude';
import { parseParamHeader, ParamHeader } from './wgslParams';
import { ExpandedDraft, expandDraft, originOf } from './wgslSourceMap';

export const DIAGNOSTIC_DEBOUNCE_MS = 150;

export interface DraftDiagnostic {
  severity: 'error' | 'warning';
  /** 1-based user line. */
  line: number;
  /** 1-based column on that line. */
  column: number;
  /** Characters the problem spans (≥ 1); the editor clamps it to the line. */
  length: number;
  message: string;
  source: 'naga' | 'include' | 'params' | 'entry-point';
}

export interface DiagnoseResult {
  /** The text that was diagnosed (callers compare it with the current text). */
  source: string;
  /** No error-severity diagnostic: safe to compile. */
  ok: boolean;
  diagnostics: DraftDiagnostic[];
  /** The include-expanded module, when expansion succeeded. */
  expanded: ExpandedDraft | null;
  header: ParamHeader;
}

export interface DiagnoseDeps {
  validate: (wgsl: string) => NagaDiagnostic;
  /** Optional: when given, a module without `@compute fn main` is an error. */
  reflect?: (wgsl: string) => NagaReflection;
  resolve: WgslIncludeResolver;
}

/** First `error:` line plus naga's `= note` lines, without the source excerpt. */
export function nagaMessage(diag: NagaDiagnostic): string {
  const lines = (diag.message ?? '').split('\n');
  const head = lines.find((l) => l.startsWith('error:'))?.replace(/^error:\s*/, '').trim() ?? 'naga rejected this shader';
  const notes = lines
    .map((l) => /^\s*=\s*(.+)$/.exec(l)?.[1]?.trim())
    .filter((n): n is string => !!n);
  return [head, ...notes].join('\n');
}

/** Width of naga's primary span: the first run of `^` under the excerpt. */
function caretLength(diag: NagaDiagnostic): number {
  for (const l of (diag.message ?? '').split('\n')) {
    const m = /│\s*(\^+)/.exec(l);
    if (m?.[1]) return m[1].length;
  }
  return 1;
}

export async function diagnoseWgsl(source: string, deps: DiagnoseDeps): Promise<DiagnoseResult> {
  const header = parseParamHeader(source);
  const diagnostics: DraftDiagnostic[] = header.problems.map((p) => ({
    severity: p.severity,
    line: p.line,
    column: 1,
    length: Number.MAX_SAFE_INTEGER,
    message: p.message,
    source: 'params',
  }));

  const expandedResult = await expandDraft(source, deps.resolve);
  let expanded: ExpandedDraft | null = null;
  if (!expandedResult.ok) {
    diagnostics.push({
      severity: 'error',
      line: expandedResult.line,
      column: 1,
      length: Number.MAX_SAFE_INTEGER,
      message: expandedResult.message,
      source: 'include',
    });
  } else {
    expanded = expandedResult.expanded;
    const result = deps.validate(expanded.text);
    if (!result.ok) {
      const origin = originOf(expanded, result.line ?? 0);
      const message = nagaMessage(result);
      if (origin.kind === 'user') {
        diagnostics.push({
          severity: 'error',
          line: origin.line,
          column: Math.max(1, result.pos ?? 1),
          length: caretLength(result),
          message,
          source: 'naga',
        });
      } else {
        diagnostics.push({
          severity: 'error',
          line: origin.includeLine,
          column: 1,
          length: Number.MAX_SAFE_INTEGER,
          message: `in ${origin.name}${origin.libraryLine > 0 ? `:${origin.libraryLine}` : ''} (included here): ${message}`,
          source: 'naga',
        });
      }
    } else if (deps.reflect) {
      const r = deps.reflect(expanded.text);
      const main = r.entryPoints?.find((ep) => ep.name === 'main');
      if (!main || main.stage !== 'compute') {
        diagnostics.push({
          severity: 'error',
          line: 1,
          column: 1,
          length: Number.MAX_SAFE_INTEGER,
          message: 'the renderer dispatches `@compute @workgroup_size(…) fn main(…)`; this module has none',
          source: 'entry-point',
        });
      }
    }
  }

  diagnostics.sort((a, b) => a.line - b.line || a.column - b.column);
  return {
    source,
    ok: !diagnostics.some((d) => d.severity === 'error'),
    diagnostics,
    expanded,
    header,
  };
}

export interface DiagnosticScheduler {
  /** Diagnose `source` after the debounce; a newer call cancels an older one. */
  schedule(source: string): void;
  /** Diagnose now (no debounce). */
  flush(source: string): Promise<DiagnoseResult>;
  dispose(): void;
}

/**
 * Debounced, latest-wins diagnostics. `onResult` only ever sees the result for
 * the most recently scheduled text; a result that finishes after a newer edit is
 * dropped. A failed diagnose (the naga artifact did not load) is reported once as
 * a warning, not as a broken shader.
 */
export function createDiagnosticScheduler(opts: {
  diagnose: (source: string) => Promise<DiagnoseResult>;
  onResult: (result: DiagnoseResult) => void;
  onError?: (err: Error) => void;
  delayMs?: number;
}): DiagnosticScheduler {
  const delay = opts.delayMs ?? DIAGNOSTIC_DEBOUNCE_MS;
  let timer: ReturnType<typeof setTimeout> | null = null;
  let seq = 0;
  let disposed = false;

  const run = async (source: string, mine: number): Promise<DiagnoseResult> => {
    const result = await opts.diagnose(source);
    if (!disposed && mine === seq) opts.onResult(result);
    return result;
  };

  return {
    schedule(source) {
      if (disposed) return;
      if (timer) clearTimeout(timer);
      const mine = ++seq;
      timer = setTimeout(() => {
        timer = null;
        run(source, mine).catch((err: unknown) => {
          if (!disposed && mine === seq) opts.onError?.(err instanceof Error ? err : new Error(String(err)));
        });
      }, delay);
    },
    flush(source) {
      if (timer) clearTimeout(timer);
      timer = null;
      return run(source, ++seq);
    },
    dispose() {
      disposed = true;
      if (timer) clearTimeout(timer);
      timer = null;
    },
  };
}
