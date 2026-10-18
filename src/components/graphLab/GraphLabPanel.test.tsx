import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import '@testing-library/jest-dom';
import { createWaveTankGraph } from '../../renderer/multipassGraph';
import type { PassTiming } from '../../renderer/passTimings';
import type { RendererManager } from '../../renderer/RendererManager';
import {
  clearRuntimeGraphs,
  getRuntimeGraph,
  getRuntimeSimRingRequest,
  GRAPH_LAB_RUNTIME_ID,
  RuntimeSimRingRequest,
  setRuntimeGraph,
} from '../../renderer/runtimeGraphs';
import type { ShaderEntry } from '../../renderer/types';
import GraphLabPanel from './GraphLabPanel';
import { GraphLabLauncher } from './GraphLabLauncher';
import { DRAFT_STORAGE_KEY } from './useGraphLab';

const MODES = [
  { id: 'wave-tank', name: 'Wave Tank', url: 'shaders/wave-step.wgsl', category: 'simulation' },
  { id: 'plasma', name: 'Plasma', url: 'shaders/plasma.wgsl', category: 'generative' },
] as unknown as ShaderEntry[];

function fakeManager(opts: { report?: Record<string, unknown> | null; timings?: PassTiming[] } = {}) {
  const slots = new Map<number, string | null>([[0, 'plasma']]);
  const cached = new Set<string>();
  const m = {
    getSlotState: vi.fn((i: number) => ({ shaderId: slots.get(i) ?? null, enabled: true, mode: 'chained' })),
    setRuntimeGraph: vi.fn((id: string, graph, simRing: RuntimeSimRingRequest | null = null) => {
      setRuntimeGraph(id, graph, simRing);
      return true;
    }),
    isShaderCached: vi.fn((id: string) => cached.has(id)),
    loadShader: vi.fn(async (id: string) => {
      cached.add(id);
      return true;
    }),
    setSlotShader: vi.fn((i: number, id: string) => {
      slots.set(i, id || null);
    }),
    getDiagnostics: vi.fn(() => ({ webgpu: { graph: opts.report ?? null } })),
    getPassTimings: vi.fn(() => opts.timings ?? []),
  };
  return { manager: m as unknown as RendererManager, m, slots };
}

function renderPanel(manager: RendererManager | null = fakeManager().manager, modes: ShaderEntry[] = MODES) {
  const rendererRef = { current: manager };
  const onClose = vi.fn();
  const utils = render(
    <GraphLabPanel rendererRef={rendererRef} availableModes={modes} activeSlot={0} onClose={onClose} />,
  );
  return { ...utils, onClose, rendererRef };
}

const startFrom = (id: string) => fireEvent.change(screen.getByTestId('graph-lab-template'), { target: { value: id } });

beforeEach(() => {
  window.localStorage.clear();
  clearRuntimeGraphs();
});
afterEach(() => clearRuntimeGraphs());

describe('GraphLabPanel', () => {
  it('opens on a working copy of the wave-tank flagship, not a blank form', () => {
    renderPanel();
    expect(within(screen.getByTestId('graph-lab-nodes')).getAllByRole('listitem')).toHaveLength(3);
    expect(screen.getByTestId('graph-lab-diagnostics-clear')).toBeInTheDocument();
    expect(screen.getByTestId('graph-lab-run')).toBeEnabled();
    expect(screen.getByTestId('export-id')).toHaveValue('wave-tank-lab');
    expect(screen.getByTestId('sim-ring-toggle')).not.toBeChecked();
  });

  it('New starts a blank graph: nothing to run or export', () => {
    renderPanel();
    fireEvent.click(screen.getByTestId('graph-lab-new'));
    expect(screen.getByTestId('graph-lab-no-nodes')).toBeInTheDocument();
    expect(screen.getByTestId('graph-lab-run')).toBeDisabled();
    expect(screen.getByTestId('export-download')).toBeDisabled();
    expect(screen.getByTestId('export-copy')).toBeDisabled();
    // The shared validator's verdict on an empty graph.
    fireEvent.click(screen.getByTestId('graph-lab-tab-diagnostics'));
    expect(screen.getByTestId('graph-lab-diagnostic')).toHaveAttribute('data-code', 'empty-graph');
  });

  it('loads a shipped graph as a template and shows it as valid', () => {
    renderPanel();
    startFrom('wave-tank');
    const nodes = screen.getByTestId('graph-lab-nodes');
    expect(within(nodes).getAllByRole('listitem')).toHaveLength(3);
    expect(within(nodes).getByText('step')).toBeInTheDocument();
    expect(screen.getByTestId('graph-lab-diagnostics-clear')).toBeInTheDocument();
    expect(screen.getByTestId('graph-lab-run')).toBeEnabled();
    expect(screen.getByTestId('export-download')).toBeEnabled();
    expect(screen.getByTestId('export-id')).toHaveValue('wave-tank-lab');
    expect(screen.getByText('shader_definitions/simulation/wave-tank-lab.json')).toBeInTheDocument();
  });

  describe('errors from the shared validator', () => {
    const broken = JSON.stringify({
      maxPassesPerFrame: 2,
      nodes: [
        { id: 'a', entry: 'wave-step', reads: ['dataB'], writes: ['dataA'], repeat: 3 },
        { id: 'b', entry: 'not-a-real-entry', reads: ['dataA'], writes: ['color'] },
      ],
    });

    beforeEach(() => {
      renderPanel();
      fireEvent.click(screen.getByText('Import JSON'));
      fireEvent.change(screen.getByTestId('graph-lab-import-text'), { target: { value: broken } });
      fireEvent.click(screen.getByTestId('graph-lab-import'));
    });

    it('lists pass-budget, dependency and missing-entry errors with the planner’s own text', () => {
      const items = screen.getAllByTestId('graph-lab-diagnostic');
      const byCode = Object.fromEntries(items.map((el) => [el.getAttribute('data-code'), el.textContent]));
      expect(byCode['pass-budget']).toContain('graph exceeds maxPassesPerFrame: 4 > 2');
      expect(byCode.dependency).toContain('node a iter 0: reads "dataB" before any producer in this frame');
      // The repeat-3 node reports once, not once per iteration.
      expect(byCode.dependency).toContain('and on 2 more iterations');
      expect(items.filter((el) => el.getAttribute('data-code') === 'dependency')).toHaveLength(1);
      expect(byCode['missing-entry']).toContain('node b: unknown entry "not-a-real-entry"');
    });

    it('blocks Run and Export, and marks the offending node', () => {
      expect(screen.getByTestId('graph-lab-run')).toBeDisabled();
      expect(screen.getByTestId('export-download')).toBeDisabled();
      expect(within(screen.getByTestId('export-blockers')).getByText(/graph exceeds maxPassesPerFrame/)).toBeInTheDocument();
      expect(screen.getByTestId('graph-lab-node-1')).toHaveClass('has-error');
    });

    it('previews no pass budgets for a graph the planner would refuse', () => {
      fireEvent.click(screen.getByTestId('graph-lab-tab-cost'));
      expect(screen.getByText('Fix the errors to preview pass budgets.')).toBeInTheDocument();
    });
  });

  it('reports a malformed import without losing the current draft', () => {
    renderPanel();
    startFrom('wave-tank');
    fireEvent.click(screen.getByText('Import JSON'));
    fireEvent.change(screen.getByTestId('graph-lab-import-text'), { target: { value: '{nope' } });
    fireEvent.click(screen.getByTestId('graph-lab-import'));
    expect(screen.getByTestId('graph-lab-run-error')).toHaveTextContent('not valid JSON');
    expect(within(screen.getByTestId('graph-lab-nodes')).getAllByRole('listitem')).toHaveLength(3);
  });

  describe('editing', () => {
    beforeEach(() => {
      renderPanel();
      startFrom('wave-tank');
    });

    it('offers only the supported roles', () => {
      for (const role of ['read', 'dataA', 'dataB', 'dataC']) expect(screen.getByTestId(`role-reads-${role}`)).toBeInTheDocument();
      for (const role of ['color', 'dataA', 'dataB']) expect(screen.getByTestId(`role-writes-${role}`)).toBeInTheDocument();
      for (const hidden of ['reads-color', 'reads-simState', 'reads-simIndex', 'writes-read', 'writes-dataC', 'writes-simState']) {
        expect(screen.queryByTestId(`role-${hidden}`)).not.toBeInTheDocument();
      }
    });

    it('re-validates as roles change (step reading dataB, which only the later inject writes, is a cycle)', () => {
      expect(screen.getByTestId('graph-lab-diagnostics-clear')).toBeInTheDocument();
      fireEvent.click(screen.getByTestId('graph-lab-node-select-0'));
      fireEvent.click(screen.getByTestId('role-reads-dataB'));
      // inject needs step's dataA while step needs inject's dataB: they wait on each other.
      expect(screen.getByTestId('graph-lab-diagnostic')).toHaveAttribute('data-code', 'cycle');
      expect(screen.getByTestId('graph-lab-run')).toBeDisabled();
      fireEvent.click(screen.getByTestId('role-reads-dataB'));
      expect(screen.getByTestId('graph-lab-diagnostics-clear')).toBeInTheDocument();
    });

    it('edits repeat within 1–64 and updates the cost', () => {
      fireEvent.change(screen.getByTestId('node-repeat'), { target: { value: '9' } });
      fireEvent.click(screen.getByTestId('graph-lab-tab-cost'));
      expect(screen.getByTestId('graph-lab-cost')).toHaveTextContent('11 passes requested');
      fireEvent.change(screen.getByTestId('node-repeat'), { target: { value: '500' } });
      expect(screen.getByTestId('node-repeat')).toHaveValue(64);
    });

    it('shows how each quality policy truncates and what survives', () => {
      fireEvent.click(screen.getByTestId('graph-lab-tab-cost'));
      const battery = screen.getByTestId('cap-battery');
      expect(battery).toHaveTextContent('Battery');
      expect(within(battery).getByText('kept')).toBeInTheDocument();
      expect(screen.getByTestId('cap-ultra')).toHaveTextContent('Ultra');
    });

    it('lists each dispatch with its producer and copy barriers', () => {
      fireEvent.click(screen.getByTestId('graph-lab-tab-dependencies'));
      const table = screen.getByTestId('graph-lab-dependencies');
      expect(table).toHaveTextContent('previous frame');
      expect(table).toHaveTextContent('dataA → dataC');
      expect(table).toHaveTextContent('step#3');
    });

    it('reorders, duplicates and removes nodes', () => {
      fireEvent.click(screen.getByLabelText('Move render up'));
      let items = within(screen.getByTestId('graph-lab-nodes')).getAllByRole('listitem');
      expect(items[1]).toHaveTextContent('render');
      fireEvent.click(screen.getByLabelText('Duplicate step'));
      items = within(screen.getByTestId('graph-lab-nodes')).getAllByRole('listitem');
      expect(items).toHaveLength(4);
      fireEvent.click(screen.getByLabelText('Remove step-2'));
      expect(within(screen.getByTestId('graph-lab-nodes')).getAllByRole('listitem')).toHaveLength(3);
    });

    it('adds a node by searching the entry catalog (including graph secondaries)', () => {
      // The "Add node" picker comes first; the inspector's picker (which re-points the selected node) second.
      const add = screen.getAllByTestId('entry-picker-input')[0];
      if (!add) throw new Error('missing entry picker');
      fireEvent.change(add, { target: { value: 'wave-inject' } });
      fireEvent.click(screen.getByTestId('entry-option-wave-inject'));
      const items = within(screen.getByTestId('graph-lab-nodes')).getAllByRole('listitem');
      expect(items).toHaveLength(4);
      expect(items[3]).toHaveTextContent('wave-inject');
    });

    it('remembers the draft in localStorage', () => {
      fireEvent.change(screen.getByTestId('export-name'), { target: { value: 'My Tank' } });
      expect(JSON.parse(window.localStorage.getItem(DRAFT_STORAGE_KEY) as string)).toMatchObject({ name: 'My Tank' });
    });
  });

  describe('sim ring', () => {
    it('edits a sim-ring graph: element count, dispatch domain, sim roles, and the WASM refusal line', () => {
      renderPanel();
      startFrom('dla-crystals');
      expect(screen.getByTestId('sim-ring-toggle')).toBeChecked();
      // walkers dispatch over simState: the ring cannot be switched off under them.
      expect(screen.getByTestId('sim-ring-toggle')).toBeDisabled();
      expect(screen.getByTestId('sim-ring-count')).toHaveValue('65536');
      expect(screen.getByTestId('sim-ring-wasm')).toHaveTextContent('?renderer=wasm refuses this shader');
      expect(screen.getByTestId('node-dispatch')).toHaveValue('simState');
      expect(screen.getByTestId('role-reads-simState')).toHaveAttribute('aria-pressed', 'true');
      expect(screen.getByTestId('role-writes-simState')).toBeEnabled();
      expect(screen.queryByTestId('role-writes-simIndex')).not.toBeInTheDocument();
      expect(screen.getByTestId('node-repeat')).toBeEnabled();
      expect(screen.getByTestId('graph-lab-run')).toBeEnabled();

      fireEvent.change(screen.getByTestId('sim-ring-count'), { target: { value: '16384' } });
      expect(JSON.parse(window.localStorage.getItem(DRAFT_STORAGE_KEY) as string).envelope.simRing).toMatchObject({ stateCount: 16384 });
      expect(screen.getByTestId('graph-lab-diagnostics-clear')).toBeInTheDocument();
    });

    it('turns the ring on for a plain graph and off again', () => {
      renderPanel();
      expect(screen.queryByTestId('role-reads-simState')).not.toBeInTheDocument();
      expect(screen.queryByTestId('node-dispatch')).not.toBeInTheDocument();
      fireEvent.click(screen.getByTestId('sim-ring-toggle'));
      expect(screen.getByTestId('sim-ring-count')).toHaveValue('65536');
      expect(screen.getByTestId('role-reads-simState')).toBeInTheDocument();
      fireEvent.change(screen.getByTestId('node-dispatch'), { target: { value: 'simState' } });
      expect(screen.getByTestId('sim-ring-toggle')).toBeDisabled();
      fireEvent.change(screen.getByTestId('node-dispatch'), { target: { value: 'pixels' } });
      fireEvent.click(screen.getByTestId('sim-ring-toggle'));
      expect(screen.queryByTestId('sim-ring-count')).not.toBeInTheDocument();
      expect(screen.queryByTestId('role-reads-simState')).not.toBeInTheDocument();
    });

    it('runs a sim-ring draft with its ring request and re-arms (recompiles) when the size changes', async () => {
      const { manager, m } = fakeManager();
      renderPanel(manager);
      startFrom('dla-crystals');
      fireEvent.click(screen.getByTestId('graph-lab-run'));
      await screen.findByTestId('graph-lab-live-report');
      expect(getRuntimeSimRingRequest(GRAPH_LAB_RUNTIME_ID)).toBe(65536);
      const loadsAfterRun = m.loadShader.mock.calls.length;

      // A plain edit keeps the ring running: no recompile.
      fireEvent.change(screen.getByTestId('node-repeat'), { target: { value: '2' } });
      await waitFor(() => expect(getRuntimeGraph(GRAPH_LAB_RUNTIME_ID)?.nodes[0]?.repeat).toBe(2));
      expect(m.loadShader.mock.calls.length).toBe(loadsAfterRun);

      fireEvent.change(screen.getByTestId('sim-ring-count'), { target: { value: '4096' } });
      await waitFor(() => expect(getRuntimeSimRingRequest(GRAPH_LAB_RUNTIME_ID)).toBe(4096));
      await waitFor(() => expect(m.loadShader.mock.calls.length).toBe(loadsAfterRun + 3));
      expect(m.loadShader.mock.calls.slice(loadsAfterRun).map((c) => c[0])).toEqual([GRAPH_LAB_RUNTIME_ID, 'dla-walkers', 'dla-render']);
    });
  });

  describe('running', () => {
    it('registers the draft, binds the slot, shows the live planner report and restores on stop', async () => {
      const report = { shaderId: GRAPH_LAB_RUNTIME_ID, requested: 5, executed: 4, truncated: 1, cap: 4, errors: [] };
      const timings: PassTiming[] = [
        { key: '0:step', label: 'step', kind: 'compute', slot: 0, shaderId: GRAPH_LAB_RUNTIME_ID, nodeId: 'step', scale: 1, gpuMs: 0.42, iterations: 3 },
      ];
      const { manager, m, slots } = fakeManager({ report, timings });
      renderPanel(manager);
      startFrom('wave-tank');

      fireEvent.click(screen.getByTestId('graph-lab-run'));
      expect(await screen.findByTestId('graph-lab-live-report')).toBeInTheDocument();
      await waitFor(() => expect(screen.getByTestId('graph-lab-live-report')).toHaveTextContent('4 / 5 passes'));
      expect(screen.getByTestId('graph-lab-live-report')).toHaveTextContent('1 truncated (cap 4)');

      expect(getRuntimeGraph(GRAPH_LAB_RUNTIME_ID)).toEqual(createWaveTankGraph());
      expect(slots.get(0)).toBe(GRAPH_LAB_RUNTIME_ID);

      fireEvent.click(screen.getByTestId('graph-lab-tab-cost'));
      expect(screen.getByTestId('graph-lab-cost')).toHaveTextContent('0.42');

      fireEvent.click(screen.getByTestId('graph-lab-stop'));
      expect(slots.get(0)).toBe('plasma');
      expect(getRuntimeGraph(GRAPH_LAB_RUNTIME_ID)).toBeNull();
      expect(m.setSlotShader).toHaveBeenLastCalledWith(0, 'plasma');
      expect(screen.queryByTestId('graph-lab-live-report')).not.toBeInTheDocument();
    });

    it('applies an edit to the running graph without a second Run', async () => {
      const { manager } = fakeManager();
      renderPanel(manager);
      startFrom('wave-tank');
      fireEvent.click(screen.getByTestId('graph-lab-run'));
      await screen.findByTestId('graph-lab-live-report');
      const before = getRuntimeGraph(GRAPH_LAB_RUNTIME_ID);

      fireEvent.click(screen.getByTestId('graph-lab-node-select-0'));
      fireEvent.change(screen.getByTestId('node-repeat'), { target: { value: '2' } });
      await waitFor(() => expect(getRuntimeGraph(GRAPH_LAB_RUNTIME_ID)).not.toBe(before));
      expect(getRuntimeGraph(GRAPH_LAB_RUNTIME_ID)?.nodes[0]?.repeat).toBe(2);
    });

    it('keeps the last good graph running while an edit leaves the draft invalid', async () => {
      const { manager } = fakeManager();
      renderPanel(manager);
      startFrom('wave-tank');
      fireEvent.click(screen.getByTestId('graph-lab-run'));
      await screen.findByTestId('graph-lab-live-report');
      const good = getRuntimeGraph(GRAPH_LAB_RUNTIME_ID);

      fireEvent.click(screen.getByTestId('graph-lab-node-select-0'));
      fireEvent.click(screen.getByTestId('role-reads-dataB'));
      await act(async () => {
        await new Promise((r) => setTimeout(r, 300));
      });
      expect(screen.getByTestId('graph-lab-diagnostic')).toHaveAttribute('data-code', 'cycle');
      expect(getRuntimeGraph(GRAPH_LAB_RUNTIME_ID)).toBe(good);
    });

    it('never loads a graph with an illegal read (a role used before it is produced)', async () => {
      const { manager, m } = fakeManager();
      renderPanel(manager);
      // step reads dataB, which only the later inject writes.
      fireEvent.click(screen.getByTestId('graph-lab-node-select-0'));
      fireEvent.click(screen.getByTestId('role-reads-dataB'));
      expect(screen.getByTestId('graph-lab-run')).toBeDisabled();
      fireEvent.click(screen.getByTestId('graph-lab-run'));
      await act(async () => {
        await new Promise((r) => setTimeout(r, 300));
      });
      expect(m.loadShader).not.toHaveBeenCalled();
      expect(m.setRuntimeGraph).not.toHaveBeenCalled();
      expect(m.setSlotShader).not.toHaveBeenCalled();
    });

    it('surfaces a compile failure instead of binding the slot', async () => {
      const { manager, m, slots } = fakeManager();
      m.loadShader.mockImplementation(async (id: string) => id !== 'wave-inject');
      renderPanel(manager);
      startFrom('wave-tank');
      fireEvent.click(screen.getByTestId('graph-lab-run'));
      expect(await screen.findByTestId('graph-lab-run-error')).toHaveTextContent('Could not compile "wave-inject".');
      expect(slots.get(0)).toBe('plasma');
    });

    it('puts the slot back when the Lab is closed', async () => {
      const { manager, slots } = fakeManager();
      const { unmount } = renderPanel(manager);
      startFrom('wave-tank');
      fireEvent.click(screen.getByTestId('graph-lab-run'));
      await screen.findByTestId('graph-lab-live-report');
      expect(slots.get(0)).toBe(GRAPH_LAB_RUNTIME_ID);
      unmount();
      expect(slots.get(0)).toBe('plasma');
      expect(getRuntimeGraph(GRAPH_LAB_RUNTIME_ID)).toBeNull();
    });

    it('notices when another shader takes the slot and stops claiming to run', async () => {
      const { manager, slots } = fakeManager();
      renderPanel(manager);
      startFrom('wave-tank');
      fireEvent.click(screen.getByTestId('graph-lab-run'));
      await screen.findByTestId('graph-lab-live-report');
      slots.set(0, 'kaleidoscope');
      await waitFor(() => expect(screen.queryByTestId('graph-lab-live-report')).not.toBeInTheDocument(), { timeout: 3000 });
      expect(screen.getByTestId('graph-lab-run')).toBeInTheDocument();
    });
  });

  it('closes', () => {
    const { onClose } = renderPanel();
    fireEvent.click(screen.getByTestId('graph-lab-close'));
    expect(onClose).toHaveBeenCalled();
  });
});

describe('GraphLabLauncher', () => {
  it('ships a button; the workspace loads on demand', async () => {
    const rendererRef = { current: fakeManager().manager };
    render(<GraphLabLauncher rendererRef={rendererRef} availableModes={MODES} activeSlot={0} />);
    expect(screen.queryByTestId('graph-lab')).not.toBeInTheDocument();
    fireEvent.click(screen.getByTestId('graph-lab-toggle'));
    expect(await screen.findByTestId('graph-lab')).toBeInTheDocument();
    expect(screen.getByTestId('graph-lab-toggle')).toHaveAttribute('aria-expanded', 'true');
    fireEvent.click(screen.getByTestId('graph-lab-close'));
    await waitFor(() => expect(screen.queryByTestId('graph-lab')).not.toBeInTheDocument());
  });
});
