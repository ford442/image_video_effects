/**
 * #1311 WP-A item 8 — the WASM bridge and src/config/vramBudget.ts share one OOM-cap contract.
 * The emitted bridge is unbundled, so the primitives live in bridge/state.ts and vramBudget re-exports them.
 */
import fs from 'fs';
import path from 'path';
import * as vram from '../../config/vramBudget';
import * as bridgeState from './state';

describe('bridge ↔ vramBudget OOM cap contract', () => {
  it('vramBudget re-exports the bridge primitives (single definition)', () => {
    expect((bridgeState as Record<string, unknown>).HISTORY_OOM_CAP_KEY).toBe('px_history_oom_cap');
    expect(vram.HISTORY_OOM_CAP_KEY).toBe((bridgeState as Record<string, unknown>).HISTORY_OOM_CAP_KEY);
    expect(vram.getHistoryWorkingSizeCap).toBe((bridgeState as Record<string, unknown>).getHistoryWorkingSizeCap);
  });

  it('init.ts does not hardcode the sessionStorage key or re-derive the cap', () => {
    const src = fs.readFileSync(path.join(__dirname, 'init.ts'), 'utf8');
    expect(src).not.toContain("'px_history_oom_cap'");
    expect(src).toMatch(/getHistoryWorkingSizeCap\(\)/);
  });
});
