import { SIM_STATE_COUNT_CHOICES } from '../../graphLab/graphDraft';
import type { RuntimeSimRingRequest } from '../../renderer/runtimeGraphs';
import { SIM_STATE_ELEMENT_BYTES } from '../../renderer/webgpu/simRing';

export interface SimRingSectionProps {
  /** The draft's ring request, or null while the draft does not use the ring. */
  request: RuntimeSimRingRequest | null;
  /** A node still uses a sim role or a simState dispatch, so the ring cannot be turned off. */
  locked: boolean;
  onToggle: (enabled: boolean) => void;
  onStateCount: (stateCount: number) => void;
}

const mib = (elements: number) => ((elements * SIM_STATE_ELEMENT_BYTES) / 1048576).toFixed(2);

/**
 * The opt-in @group(1) sim ring (src/contracts/bind_group1.json) as the draft's
 * `simRing` request. It adds no binding: the renderer arms the ring only when an
 * entry that declares @group(1) compiles, and binds it only to those entries.
 */
export function SimRingSection({ request, locked, onToggle, onStateCount }: SimRingSectionProps) {
  const on = request !== null;
  return (
    <div className="graph-lab__simring" data-testid="graph-lab-simring">
      <label className="graph-lab__field graph-lab__field--inline">
        <input
          type="checkbox"
          checked={on}
          disabled={on && locked}
          title={on && locked ? 'A node still uses simState / simIndex or a simState dispatch' : undefined}
          data-testid="sim-ring-toggle"
          onChange={(e) => onToggle(e.target.checked)}
        />{' '}
        Use the group-1 sim ring
      </label>
      {on && (
        <>
          <label className="graph-lab__field graph-lab__field--inline">
            <span>State elements</span>
            <select
              value={request.stateCount}
              data-testid="sim-ring-count"
              onChange={(e) => onStateCount(Number(e.target.value))}
            >
              {SIM_STATE_COUNT_CHOICES.map((n) => (
                <option key={n} value={n}>
                  {n.toLocaleString('en-US')} ({mib(n)} MiB)
                </option>
              ))}
              {!SIM_STATE_COUNT_CHOICES.includes(request.stateCount) && (
                <option value={request.stateCount}>{request.stateCount.toLocaleString('en-US')} (as imported)</option>
              )}
            </select>
          </label>
          <ul className="graph-lab__notes">
            <li>
              <code>simState</code> (vec4&lt;f32&gt; per element) + its <code>simIndex</code> snapshot, {mib(request.stateCount)} MiB
              each. The ring takes the largest out-of-memory ladder rung that fits; an OOM caps it for the session.
            </li>
            <li>
              Bound only to entries whose WGSL declares <code>@group(1)</code>. Other entries keep the group-0 layout; a{' '}
              <code>simState</code> dispatch of one runs only once a group-1 entry has armed the ring.
            </li>
            <li>Running, a size change recompiles the entries and re-seeds the ring (frame 0).</li>
            <li data-testid="sim-ring-wasm">
              <code>?renderer=wasm</code> refuses this shader: the C++ backend has one bind group and skips <code>@group(1)</code>{' '}
              WGSL before loading it.
            </li>
          </ul>
        </>
      )}
    </div>
  );
}
