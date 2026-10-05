// ═══════════════════════════════════════════════════════════════════════════════
//  oscRouter.ts
//  Pure OSC address → Pixelocity action mapping. Address space (docs/VJ_STUDIO.md):
//
//    /pixelocity/slot/{0-5}/param/{x|y|z|w}   f   slider value 0..1
//    /pixelocity/slot/{0-5}/shader            s   shader id ("none" clears)
//    /pixelocity/transition                   s?  fire the next transition
//    /pixelocity/audio/amount                 f   host audio amount 0..1
// ═══════════════════════════════════════════════════════════════════════════════

import slotLimitsContract from '../../contracts/slot_limits.json';
import type { LiveActionsHandle } from '../controlBindings';
import type { OscArg, OscMessage } from './oscPacket';

export const OSC_ADDRESS_PREFIX = '/pixelocity';
const MAX_SLOT_INDEX = slotLimitsContract.maxPhysicalSlots - 1;

const PARAM_KEYS: Record<string, 'zoomParam1' | 'zoomParam2' | 'zoomParam3' | 'zoomParam4'> = {
  x: 'zoomParam1',
  y: 'zoomParam2',
  z: 'zoomParam3',
  w: 'zoomParam4',
};

export type OscAction =
  | { type: 'setSlotParam'; slot: number; param: string; value: number }
  | { type: 'setSlotShader'; slot: number; shaderId: string }
  | { type: 'triggerTransition'; name?: string }
  | { type: 'setAudioAmount'; value: number };

/** What the router drives; setSlotParam/triggerTransition reuse the MIDI handle. */
export interface OscActionsHandle extends Pick<LiveActionsHandle, 'setSlotParam' | 'triggerTransition'> {
  setSlotShader: (slot: number, shaderId: string) => void;
  setAudioAmount: (value: number) => void;
}

const clamp01 = (v: number) => Math.max(0, Math.min(1, v));

function numericArg(args: OscArg[]): number | null {
  const a = args[0];
  if (typeof a === 'number' && Number.isFinite(a)) return a;
  if (typeof a === 'boolean') return a ? 1 : 0;
  return null;
}

function parseSlot(raw: string): number | null {
  if (!/^\d+$/.test(raw)) return null;
  const slot = Number(raw);
  return slot <= MAX_SLOT_INDEX ? slot : null;
}

/** Map one message to an action, or null if it is not ours / malformed. */
export function routeOscMessage(msg: OscMessage): OscAction | null {
  const parts = msg.address.split('/').filter(Boolean);
  if (parts[0] !== OSC_ADDRESS_PREFIX.slice(1)) return null;

  if (parts[1] === 'slot' && parts.length >= 4) {
    const slot = parseSlot(parts[2]);
    if (slot === null) return null;
    if (parts[3] === 'param' && parts.length === 5) {
      const param = PARAM_KEYS[parts[4]];
      const value = numericArg(msg.args);
      if (!param || value === null) return null;
      return { type: 'setSlotParam', slot, param, value: clamp01(value) };
    }
    if (parts[3] === 'shader' && parts.length === 4) {
      const id = msg.args[0];
      if (typeof id !== 'string' || id.length === 0 || id.length > 128) return null;
      return { type: 'setSlotShader', slot, shaderId: id };
    }
    return null;
  }

  if (parts[1] === 'transition' && parts.length === 2) {
    // Momentary buttons send 1 on press and 0 on release — only fire on press.
    const n = numericArg(msg.args);
    if (n !== null && n <= 0) return null;
    const name = typeof msg.args[0] === 'string' ? (msg.args[0] as string) : undefined;
    return name ? { type: 'triggerTransition', name } : { type: 'triggerTransition' };
  }

  if (parts[1] === 'audio' && parts[2] === 'amount' && parts.length === 3) {
    const value = numericArg(msg.args);
    if (value === null) return null;
    return { type: 'setAudioAmount', value: clamp01(value) };
  }

  return null;
}

/** Route + dispatch; returns the action taken (for status / tests). */
export function dispatchOscMessage(msg: OscMessage, handle: OscActionsHandle): OscAction | null {
  const action = routeOscMessage(msg);
  if (!action) return null;
  switch (action.type) {
    case 'setSlotParam': handle.setSlotParam(action.slot, action.param, action.value); break;
    case 'setSlotShader': handle.setSlotShader(action.slot, action.shaderId); break;
    case 'triggerTransition': handle.triggerTransition(); break;
    case 'setAudioAmount': handle.setAudioAmount(action.value); break;
  }
  return action;
}
