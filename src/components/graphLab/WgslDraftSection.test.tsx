import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import '@testing-library/jest-dom';
import { EditorView } from '@codemirror/view';
import { forEachDiagnostic } from '@codemirror/lint';
import type { RendererManager } from '../../renderer/RendererManager';
import type { ShaderEntry } from '../../renderer/types';
import { wgslRuntimeIds } from '../../graphLab/runDraft';
import type { DiagnoseDeps } from '../../graphLab/wgslDiagnostics';
import { WGSL_DRAFTS_STORAGE_KEY, WGSL_TEMPLATE } from '../../graphLab/wgslDraft';
import type { NagaReflector, NagaValidator } from '../../utils/nagaWasm';
import { withBundledLibraries } from '../../wasm/bridge/wgslLibraries';
import GraphLabPanel from './GraphLabPanel';

const ROOT = path.resolve(__dirname, '../../..');
const MODES = [{ id: 'plasma', name: 'Plasma', url: 'shaders/plasma.wgsl', category: 'generative' }] as unknown as ShaderEntry[];

let nagaDeps: DiagnoseDeps;
beforeAll(async () => {
  const mod = (await import(pathToFileURL(path.join(ROOT, 'public/wasm/naga_wasm.js')).href)) as {
    createNagaValidator(o: { bytes: BufferSource }): Promise<NagaValidator & NagaReflector>;
  };
  const naga = await mod.createNagaValidator({ bytes: fs.readFileSync(path.join(ROOT, 'public/wasm/naga_wasm.wasm')) });
  nagaDeps = {
    validate: (s) => naga.validate(s),
    reflect: (s) => naga.reflect(s),
    resolve: withBundledLibraries(async () => null),
  };
});

// CodeMirror measures layout; jsdom has no Range rects.
beforeAll(() => {
  const rect = { x: 0, y: 0, width: 0, height: 0, top: 0, left: 0, right: 0, bottom: 0, toJSON: () => ({}) };
  Range.prototype.getClientRects = () => ({ length: 0, item: () => null, [Symbol.iterator]: [][Symbol.iterator] }) as unknown as DOMRectList;
  Range.prototype.getBoundingClientRect = () => rect as DOMRect;
});

beforeEach(() => window.localStorage.clear());

function fakeManager(compiles: (wgsl: string) => boolean = () => true) {
  const slots = new Map<number, string>([[0, 'plasma']]);
  const m = {
    getSlotState: vi.fn((i: number) => ({ shaderId: slots.get(i) ?? null, enabled: true, mode: 'chained' })),
    setRuntimeGraph: vi.fn(() => true),
    isShaderCached: vi.fn(() => false),
    loadShader: vi.fn(async (_id: string, url: string) => compiles(await (await fetch(url)).text())),
    setSlotShader: vi.fn((i: number, id: string) => void slots.set(i, id)),
    setSlotParams: vi.fn(),
    getDiagnostics: vi.fn(() => ({ webgpu: { graph: null } })),
    getPassTimings: vi.fn(() => []),
  };
  return { m, slots, manager: m as unknown as RendererManager };
}

async function renderOpen(manager: RendererManager) {
  const deps = () => Promise.resolve(nagaDeps);
  render(
    <GraphLabPanel rendererRef={{ current: manager }} availableModes={MODES} activeSlot={0} onClose={vi.fn()} wgslOpen wgslDiagnoseDeps={deps} />,
  );
  const content = await screen.findByTestId('graph-lab-wgsl-editor-content', {}, { timeout: 5000 });
  const view = EditorView.findFromDOM(content);
  if (!view) throw new Error('no EditorView');
  await screen.findByTestId('graph-lab-wgsl-valid');
  return view;
}

const type = (view: EditorView, from: string, to: string) =>
  act(() => {
    const at = view.state.doc.toString().indexOf(from);
    view.dispatch({ changes: { from: at, to: at + from.length, insert: to } });
  });

describe('Graph Lab WGSL editor', () => {
  // Blob URLs → text, for the fake renderer's loadShader.
  const blobs = new Map<string, string>();
  beforeAll(() => {
    let n = 0;
    URL.createObjectURL = vi.fn((b: Blob) => {
      const url = `blob:test/${n++}`;
      const reader = new FileReader();
      reader.onload = () => blobs.set(url, String(reader.result));
      reader.readAsText(b);
      return url;
    });
    URL.revokeObjectURL = vi.fn();
    global.fetch = vi.fn(async (u: RequestInfo | URL) => {
      for (let i = 0; i < 50 && !blobs.has(String(u)); i++) await new Promise((r) => setTimeout(r, 2));
      return new Response(blobs.get(String(u)) ?? '', { status: 200 });
    }) as typeof fetch;
  });

  it('opens on the template, lists its @param sliders and validates it with naga', async () => {
    const { manager } = fakeManager();
    const view = await renderOpen(manager);
    expect(view.state.doc.toString()).toBe(WGSL_TEMPLATE);
    expect(screen.getByTestId('graph-lab-wgsl-param-speed')).toBeInTheDocument();
    expect(screen.getByTestId('graph-lab-wgsl-param-tint')).toBeInTheDocument();
    expect(screen.getByTestId('graph-lab-wgsl-run')).toBeEnabled();
  });

  it('a typed error shows naga\'s diagnostic on the user line, in the banner and the lint state', async () => {
    const { manager } = fakeManager();
    const view = await renderOpen(manager);
    type(view, 'let t = u.config.x', 'let t = u.confg.x');
    const banner = await screen.findByTestId('graph-lab-wgsl-error');
    const line = WGSL_TEMPLATE.split('\n').findIndex((l) => l.includes('let t = u.config.x')) + 1;
    expect(banner.textContent).toMatch(new RegExp(`^L${line}:`));
    const marks: number[] = [];
    forEachDiagnostic(view.state, (_d, from) => marks.push(view.state.doc.lineAt(from).number));
    expect(marks).toEqual([line]);
    expect(screen.getByTestId('graph-lab-wgsl-run')).toBeDisabled();
  });

  it('runs on a clean validate, keeps the last good pipeline on an invalid edit, and hot-swaps the next clean one', async () => {
    const { manager, m, slots } = fakeManager();
    const view = await renderOpen(manager);
    fireEvent.click(screen.getByTestId('graph-lab-wgsl-run'));
    const [a, b] = wgslRuntimeIds(0);
    await waitFor(() => expect(slots.get(0)).toBe(a));
    expect(m.setSlotParams).toHaveBeenCalledWith(0, 1, 0.3, 0.5, 0);
    // The compiled module is the include-expanded one: the GPU never has to resolve an include.
    const compiled = blobs.get(String(m.loadShader.mock.calls[0]?.[1])) ?? '';
    expect(compiled).toContain('@group(0) @binding(1) var readTexture');
    expect(compiled).not.toMatch(/^#include/m);

    type(view, 'let t = u.config.x', 'let t = nope');
    await screen.findByTestId('graph-lab-wgsl-error');
    await new Promise((r) => setTimeout(r, 50));
    expect(m.loadShader).toHaveBeenCalledTimes(1);
    expect(slots.get(0)).toBe(a);

    type(view, 'let t = nope', 'let t = u.config.x * 2.0');
    await waitFor(() => expect(slots.get(0)).toBe(b));
    expect(screen.getByTestId('graph-lab-wgsl-valid').textContent).toMatch(/live/);

    fireEvent.click(screen.getByTestId('graph-lab-wgsl-stop'));
    expect(slots.get(0)).toBe('plasma');
  });

  it('a GPU compile failure after naga keeps the old pipeline and says so', async () => {
    const { manager, slots } = fakeManager((wgsl) => !wgsl.includes('2.5'));
    const view = await renderOpen(manager);
    fireEvent.click(screen.getByTestId('graph-lab-wgsl-run'));
    const [a] = wgslRuntimeIds(0);
    await waitFor(() => expect(slots.get(0)).toBe(a));
    type(view, '0.02 *', '0.02 * 2.5 *');
    expect(await screen.findByTestId('graph-lab-wgsl-swap-error')).toHaveTextContent(/last good one keeps running/);
    expect(slots.get(0)).toBe(a);
  });

  it('keeps keystrokes typed in the editor away from the app\'s window shortcuts', async () => {
    const { manager } = fakeManager();
    await renderOpen(manager);
    const onWindowKey = vi.fn();
    window.addEventListener('keydown', onWindowKey);
    fireEvent.keyDown(screen.getByTestId('graph-lab-wgsl-editor-content'), { key: ' ' });
    fireEvent.keyDown(screen.getByTestId('graph-lab-wgsl-editor-content'), { key: 'r' });
    window.removeEventListener('keydown', onWindowKey);
    expect(onWindowKey).not.toHaveBeenCalled();
  });

  it('keeps one draft per slot in localStorage', async () => {
    const { manager } = fakeManager();
    const view = await renderOpen(manager);
    type(view, '// @param tint 0 1 0.5 Warm tint', '// @param tint 0 1 0.9 Warm tint');
    const stored = JSON.parse(window.localStorage.getItem(WGSL_DRAFTS_STORAGE_KEY) ?? '{}');
    expect(stored.slots['0'].source).toContain('0 1 0.9 Warm tint');
  });

  it('Save as shader is offered once the draft validates', async () => {
    const { manager } = fakeManager();
    await renderOpen(manager);
    expect(screen.getByTestId('graph-lab-wgsl-save')).toBeEnabled();
    fireEvent.change(screen.getByTestId('graph-lab-wgsl-id'), { target: { value: 'plasma' } });
    expect(screen.getByTestId('graph-lab-wgsl-save-errors')).toHaveTextContent(/already exists/);
    expect(screen.getByTestId('graph-lab-wgsl-save')).toBeDisabled();
  });
});
