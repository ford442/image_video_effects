/** validate.ts — structural checks for persisted / transported routes (#1513). */

import type { ModSource, ResolvedRoute, Route } from './types';
import { AUDIO_BANDS, LFO_SHAPES, MOD_CURVES, MOD_TARGET_PARAMS, SEQUENCER_STEPS } from './types';

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v);
const isNum = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v);
const isStr = (v: unknown): v is string => typeof v === 'string';
const oneOf = <T extends string>(list: readonly T[], v: unknown): v is T => isStr(v) && (list as readonly string[]).includes(v);

/** Returns a list of problems with `v` as a ModSource, empty when valid. */
export function sourceErrors(v: unknown, path = 'source'): string[] {
  if (!isObj(v)) return [`${path}: must be an object`];
  const e: string[] = [];
  const num = (k: string, opt = false) => {
    if (opt && v[k] === undefined) return;
    if (!isNum(v[k])) e.push(`${path}.${k}: must be a finite number`);
  };
  switch (v.kind) {
    case 'lfo':
      if (!oneOf(LFO_SHAPES, v.shape)) e.push(`${path}.shape: unknown LFO shape`);
      if (v.unit !== 'hz' && v.unit !== 'beats') e.push(`${path}.unit: must be 'hz' or 'beats'`);
      num('rate'); num('phase', true); num('seed', true);
      break;
    case 'adsr': {
      num('attack'); num('decay'); num('sustain'); num('release');
      const g = v.gate;
      if (!isObj(g)) e.push(`${path}.gate: must be an object`);
      else if (g.from === 'external') { if (!isStr(g.key)) e.push(`${path}.gate.key: must be a string`); }
      else if (g.from === 'beat') { if (!isNum(g.every) || !isNum(g.length)) e.push(`${path}.gate: every/length must be numbers`); }
      else if (g.from !== 'onset') e.push(`${path}.gate.from: unknown gate`);
      break;
    }
    case 'audio':
      if (!oneOf(AUDIO_BANDS, v.band)) e.push(`${path}.band: unknown audio band`);
      break;
    case 'sequencer':
      if (!Array.isArray(v.steps) || v.steps.length !== SEQUENCER_STEPS || !v.steps.every(isNum)) {
        e.push(`${path}.steps: must be ${SEQUENCER_STEPS} numbers`);
      }
      num('stepBeats');
      break;
    case 'random':
      num('seed'); num('rate'); num('step');
      break;
    case 'external':
      if (!isStr(v.key)) e.push(`${path}.key: must be a string`);
      break;
    default:
      e.push(`${path}.kind: unknown source kind`);
  }
  return e;
}

export function routeErrors(v: unknown, path = 'route'): string[] {
  if (!isObj(v)) return [`${path}: must be an object`];
  const e: string[] = [];
  if (!isStr(v.id) || !v.id) e.push(`${path}.id: must be a non-empty string`);
  e.push(...sourceErrors(v.source, `${path}.source`));
  const t = v.target;
  if (!isObj(t) || !Number.isInteger(t.slot) || (t.slot as number) < 0) e.push(`${path}.target.slot: must be an integer >= 0`);
  if (!isObj(t) || !oneOf(MOD_TARGET_PARAMS, t.param)) e.push(`${path}.target.param: must be p1..p4 or opacity`);
  if (!isNum(v.depth)) e.push(`${path}.depth: must be a finite number`);
  if (!isNum(v.offset)) e.push(`${path}.offset: must be a finite number`);
  if (!oneOf(MOD_CURVES, v.curve)) e.push(`${path}.curve: must be linear, exp or smooth`);
  return e;
}

export const isRoute = (v: unknown): v is Route => routeErrors(v).length === 0;

export function isResolvedRoute(v: unknown): v is ResolvedRoute {
  return isRoute(v) && isNum((v as unknown as ResolvedRoute).min) && isNum((v as unknown as ResolvedRoute).max);
}

/** Deep copy of just the Route fields (drops min/max and any extra keys). */
export function toRoute(r: Route): Route {
  return {
    id: r.id,
    source: JSON.parse(JSON.stringify(r.source)) as ModSource,
    target: { slot: r.target.slot, param: r.target.param },
    depth: r.depth,
    offset: r.offset,
    curve: r.curve,
  };
}
