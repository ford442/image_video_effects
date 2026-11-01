/**
 * Inline WGSL editor (CodeMirror 6). Its own lazy chunk, "graph-lab-editor",
 * inside the lazy Lab: neither main.js nor the Lab panel chunk carries CodeMirror.
 *
 * The editor is a view: the text lives in the parent (one draft per slot), the
 * diagnostics come from wgslDiagnostics.ts and are pushed with setDiagnostics,
 * and completions are generated from the prelude (wgslCompletions.ts).
 */

import { useEffect, useRef } from 'react';
import { autocompletion, closeBrackets, closeBracketsKeymap, Completion, CompletionContext, completionKeymap } from '@codemirror/autocomplete';
import { defaultKeymap, history, historyKeymap, indentWithTab } from '@codemirror/commands';
import { bracketMatching, syntaxHighlighting } from '@codemirror/language';
import { Diagnostic, lintGutter, lintKeymap, setDiagnostics } from '@codemirror/lint';
import { EditorState, Text } from '@codemirror/state';
import { drawSelection, EditorView, highlightActiveLine, highlightActiveLineGutter, keymap, lineNumbers } from '@codemirror/view';
import type { CompletionSpec } from '../../../graphLab/wgslCompletions';
import type { DraftDiagnostic } from '../../../graphLab/wgslDiagnostics';
import { wgslHighlight, wgslLanguage } from './wgslLanguage';

export interface WgslEditorProps {
  value: string;
  onChange: (value: string) => void;
  diagnostics: readonly DraftDiagnostic[];
  completions: readonly CompletionSpec[];
  /** Accessible name of the text area. */
  label?: string;
}

/** 1-based line/column + length → a document range, clamped to the line. */
export function toEditorDiagnostics(doc: Text, diags: readonly DraftDiagnostic[]): Diagnostic[] {
  return diags.map((d) => {
    const line = doc.line(Math.min(Math.max(1, d.line), doc.lines));
    const from = Math.min(line.to, line.from + Math.max(0, d.column - 1));
    const to = Math.max(from, Math.min(line.to, from + Math.max(1, d.length)));
    return {
      from,
      // An empty range (end of line, empty line) still needs a marker in the gutter.
      to: to === from && from < doc.length ? from + 1 : to,
      severity: d.severity,
      message: d.message,
      source: d.source,
    };
  });
}

const editorTheme = EditorView.theme(
  {
    '&': { backgroundColor: '#0d1117', color: '#c9d1d9', fontSize: '12px', height: '100%' },
    '.cm-scroller': { fontFamily: 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace', lineHeight: '1.45' },
    '.cm-content': { caretColor: '#c9d1d9' },
    '.cm-gutters': { backgroundColor: '#0d1117', color: '#6e7681', border: 'none' },
    '.cm-activeLine, .cm-activeLineGutter': { backgroundColor: 'rgba(110, 118, 129, 0.12)' },
    '&.cm-focused .cm-selectionBackground, .cm-selectionBackground': { backgroundColor: 'rgba(56, 139, 253, 0.35)' },
    '.cm-tooltip': { backgroundColor: '#161b22', border: '1px solid #30363d', color: '#c9d1d9' },
  },
  { dark: true },
);

export default function WgslEditor({ value, onChange, diagnostics, completions, label = 'WGSL source' }: WgslEditorProps) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const onChangeRef = useRef(onChange);
  onChangeRef.current = onChange;
  const completionsRef = useRef(completions);
  completionsRef.current = completions;

  useEffect(() => {
    if (!host.current) return undefined;
    const complete = (ctx: CompletionContext) => {
      const word = ctx.matchBefore(/[@\w.]+/);
      if (!word || (word.from === word.to && !ctx.explicit)) return null;
      const options: Completion[] = completionsRef.current.map((c) => ({
        label: c.label,
        type: c.type,
        detail: c.detail,
        info: c.info,
        apply: c.apply,
      }));
      return { from: word.from, options, validFor: /^[@\w.]*$/ };
    };
    const v = new EditorView({
      parent: host.current,
      state: EditorState.create({
        doc: value,
        extensions: [
          lineNumbers(),
          highlightActiveLineGutter(),
          highlightActiveLine(),
          history(),
          drawSelection(),
          bracketMatching(),
          closeBrackets(),
          wgslLanguage,
          syntaxHighlighting(wgslHighlight),
          autocompletion({ override: [complete] }),
          lintGutter(),
          keymap.of([...closeBracketsKeymap, ...defaultKeymap, ...historyKeymap, ...completionKeymap, ...lintKeymap, indentWithTab]),
          EditorView.contentAttributes.of({ 'aria-label': label, 'data-testid': 'graph-lab-wgsl-editor-content' }),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) onChangeRef.current(u.state.doc.toString());
          }),
          editorTheme,
        ],
      }),
    });
    view.current = v;
    // The app's window-level shortcuts (Space, a, g, r, digits…) only skip <input>/<textarea>;
    // keep keystrokes typed here from reaching them. CodeMirror has already handled them on its content.
    const contain = (e: KeyboardEvent) => e.stopPropagation();
    const hostEl = host.current;
    hostEl.addEventListener('keydown', contain);
    hostEl.addEventListener('keyup', contain);
    return () => {
      hostEl.removeEventListener('keydown', contain);
      hostEl.removeEventListener('keyup', contain);
      v.destroy();
      view.current = null;
    };
    // The view is created once; `value` changes from outside are applied below.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Text replaced from outside (slot switch, reset to the template).
  useEffect(() => {
    const v = view.current;
    if (!v || v.state.doc.toString() === value) return;
    v.dispatch({ changes: { from: 0, to: v.state.doc.length, insert: value } });
  }, [value]);

  useEffect(() => {
    const v = view.current;
    if (!v) return;
    v.dispatch(setDiagnostics(v.state, toEditorDiagnostics(v.state.doc, diagnostics)));
  }, [diagnostics]);

  return <div ref={host} className="graph-lab__wgsl-editor" data-testid="graph-lab-wgsl-editor" />;
}
