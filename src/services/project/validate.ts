import type { RenderQualityMode } from '../../config/performancePolicy';
import type { SlotParams } from '../../renderer/types';
import { sanitizeBindings, type ControlBinding } from '../controlBindings';
import {
  MAX_SHARED_SLOTS,
  SHARED_CHAIN_VERSION,
  type SharedChain,
  type SharedChainSlot,
} from '../layerChainShare';
import {
  MAX_TIMELINE_EVENTS,
  parseVjSetExport,
  type VjSetExportPayload,
  type VjTimeline,
} from '../vjSetExport';
import {
  PROJECT_APP_NAME,
  PROJECT_FILE_SCHEMA_VERSION,
  type ProjectFile,
  type ProjectSource,
  type ProjectValidationResult,
} from './types';
import { compactSlotLayerErrors } from '../../renderer/layerState';
import { routeErrors, toRoute } from '../../modulation/validate';
import type { Route } from '../../modulation/types';

/** Accepted nits for render.hdr (a range any real panel and any sane paper white fit in). */
export const HDR_NITS_RANGE = { min: 80, max: 10000 } as const;

const TOP_LEVEL_KEYS = ['schemaVersion', 'app', 'createdAt', 'chain', 'activeSlot', 'source', 'render', 'audio', 'timeline', 'modulation'];
/** Upper bound on routes in one project. */
export const MAX_MODULATION_ROUTES = 256;
const SLOT_PARAM_KEYS: Array<keyof SlotParams> = [
  'zoomParam1',
  'zoomParam2',
  'zoomParam3',
  'zoomParam4',
  'lightStrength',
  'ambient',
  'normalStrength',
  'fogFalloff',
  'depthThreshold',
];
const QUALITY_MODES = new Set<RenderQualityMode>(['battery', 'balanced', 'ultra', 'auto']);
const SOURCE_KINDS = new Set(['image', 'video', 'webcam', 'generative', 'stream', 'none']);
const TIMELINE_PARAM_KEYS = new Set(['zoomParam1', 'zoomParam2', 'zoomParam3', 'zoomParam4']);
const FORBIDDEN_REF = /^(?:data|blob):|MediaStream|permission/i;

function isRecord(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function checkExtraKeys(value: Record<string, unknown>, allowed: readonly string[], path: string, errors: string[]): void {
  const allowedSet = new Set(allowed);
  for (const key of Object.keys(value)) {
    if (!allowedSet.has(key)) errors.push(`${path}.${key} is not allowed`);
  }
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

export function isSafeProjectRef(value: unknown): value is string {
  return typeof value === 'string'
    && value.trim().length > 0
    && value.length <= 4096
    && !FORBIDDEN_REF.test(value.trim());
}

function validateChain(raw: unknown, path: string, errors: string[]): SharedChain | null {
  if (!isRecord(raw)) {
    errors.push(`${path} must be an object`);
    return null;
  }
  checkExtraKeys(raw, ['v', 'slots'], path, errors);
  if (raw.v !== SHARED_CHAIN_VERSION) errors.push(`${path}.v must be ${SHARED_CHAIN_VERSION}`);
  if (!Array.isArray(raw.slots)) {
    errors.push(`${path}.slots must be an array`);
    return null;
  }
  if (raw.slots.length > MAX_SHARED_SLOTS) {
    errors.push(`${path}.slots must contain at most ${MAX_SHARED_SLOTS} entries`);
  }

  const slots: SharedChainSlot[] = [];
  raw.slots.slice(0, MAX_SHARED_SLOTS).forEach((slotRaw, index) => {
    const slotPath = `${path}.slots[${index}]`;
    if (!isRecord(slotRaw)) {
      errors.push(`${slotPath} must be an object`);
      return;
    }
    checkExtraKeys(slotRaw, ['shaderId', 'params', 'enabled', 'mode', 'b', 'o', 'm', 'k'], slotPath, errors);
    if (slotRaw.shaderId !== null && typeof slotRaw.shaderId !== 'string') {
      errors.push(`${slotPath}.shaderId must be a string or null`);
      return;
    }
    if (typeof slotRaw.shaderId === 'string' && slotRaw.shaderId.length > 128) {
      errors.push(`${slotPath}.shaderId must be at most 128 characters`);
    }
    const slot: SharedChainSlot = { shaderId: slotRaw.shaderId as string | null };
    if (slotRaw.params !== undefined) {
      if (!isRecord(slotRaw.params)) {
        errors.push(`${slotPath}.params must be an object`);
      } else {
        checkExtraKeys(slotRaw.params, SLOT_PARAM_KEYS, `${slotPath}.params`, errors);
        const params: Partial<SlotParams> = {};
        for (const key of SLOT_PARAM_KEYS) {
          const value = slotRaw.params[key];
          if (value === undefined) continue;
          if (!isFiniteNumber(value)) errors.push(`${slotPath}.params.${key} must be a finite number`);
          else params[key] = value;
        }
        slot.params = params;
      }
    }
    if (slotRaw.enabled !== undefined) {
      if (typeof slotRaw.enabled !== 'boolean') errors.push(`${slotPath}.enabled must be a boolean`);
      else slot.enabled = slotRaw.enabled;
    }
    if (slotRaw.mode !== undefined) {
      if (slotRaw.mode !== 'chained' && slotRaw.mode !== 'parallel') {
        errors.push(`${slotPath}.mode must be "chained" or "parallel"`);
      } else {
        slot.mode = slotRaw.mode;
      }
    }
    // Compositor fields (#1512): strict here, unlike chain links which degrade unknown values.
    const layerErrors = compactSlotLayerErrors(slotRaw, slotPath);
    errors.push(...layerErrors);
    if (layerErrors.length === 0) {
      if (typeof slotRaw.b === 'string') slot.b = slotRaw.b;
      if (typeof slotRaw.o === 'number') slot.o = slotRaw.o;
      if (typeof slotRaw.m === 'string') slot.m = slotRaw.m;
      if (typeof slotRaw.k === 'number') slot.k = slotRaw.k;
    }
    slots.push(slot);
  });

  return { v: SHARED_CHAIN_VERSION, slots };
}

function validateSource(raw: unknown, errors: string[]): ProjectSource | null {
  if (!isRecord(raw)) {
    errors.push('project.source must be an object');
    return null;
  }
  checkExtraKeys(raw, ['kind', 'ref', 'generativeShaderId'], 'project.source', errors);
  if (typeof raw.kind !== 'string' || !SOURCE_KINDS.has(raw.kind)) {
    errors.push('project.source.kind is not recognized');
    return null;
  }
  const source: ProjectSource = { kind: raw.kind as ProjectSource['kind'] };
  if (raw.ref !== undefined) {
    if (!isSafeProjectRef(raw.ref)) errors.push('project.source.ref must be a safe URL or catalog id (data/blob refs are forbidden)');
    else source.ref = raw.ref.trim();
  }
  if (raw.generativeShaderId !== undefined) {
    if (typeof raw.generativeShaderId !== 'string' || !raw.generativeShaderId.trim() || raw.generativeShaderId.length > 128) {
      errors.push('project.source.generativeShaderId must be a non-empty string of at most 128 characters');
    } else {
      source.generativeShaderId = raw.generativeShaderId.trim();
    }
  }
  if (['image', 'video', 'stream'].includes(source.kind) && !source.ref) {
    errors.push(`project.source.ref is required for source kind "${source.kind}"`);
  }
  if (source.kind === 'generative' && !source.generativeShaderId) {
    errors.push('project.source.generativeShaderId is required for source kind "generative"');
  }
  if (['none', 'webcam', 'generative'].includes(source.kind) && source.ref) {
    errors.push(`project.source.ref is not allowed for source kind "${source.kind}"`);
  }
  if (source.kind !== 'generative' && source.generativeShaderId) {
    errors.push(`project.source.generativeShaderId is not allowed for source kind "${source.kind}"`);
  }
  return source;
}

function validateBinding(raw: unknown, path: string, errors: string[]): raw is ControlBinding {
  if (!isRecord(raw)) {
    errors.push(`${path} must be an object`);
    return false;
  }
  checkExtraKeys(raw, ['trigger', 'action'], path, errors);
  if (!isRecord(raw.trigger) || !isRecord(raw.action)) {
    errors.push(`${path} must contain trigger and action objects`);
    return false;
  }
  checkExtraKeys(raw.trigger, ['source', 'id'], `${path}.trigger`, errors);
  if (!['midi-cc', 'midi-note', 'key'].includes(String(raw.trigger.source))) {
    errors.push(`${path}.trigger.source is not recognized`);
  }
  if (typeof raw.trigger.id !== 'string' || !raw.trigger.id || raw.trigger.id.length > 64) {
    errors.push(`${path}.trigger.id must be 1-64 characters`);
  }

  const type = raw.action.type;
  if (type === 'setSlotParam') {
    checkExtraKeys(raw.action, ['type', 'slot', 'param'], `${path}.action`, errors);
    if (!Number.isInteger(raw.action.slot) || Number(raw.action.slot) < 0 || Number(raw.action.slot) >= MAX_SHARED_SLOTS) {
      errors.push(`${path}.action.slot must be an integer from 0 to ${MAX_SHARED_SLOTS - 1}`);
    }
    if (typeof raw.action.param !== 'string' || !raw.action.param || raw.action.param.length > 128) {
      errors.push(`${path}.action.param must be 1-128 characters`);
    }
  } else if (type === 'randomizeSlot') {
    checkExtraKeys(raw.action, ['type', 'slot'], `${path}.action`, errors);
    if (!Number.isInteger(raw.action.slot) || Number(raw.action.slot) < 0 || Number(raw.action.slot) >= MAX_SHARED_SLOTS) {
      errors.push(`${path}.action.slot must be an integer from 0 to ${MAX_SHARED_SLOTS - 1}`);
    }
  } else if (['randomizeAll', 'triggerTransition', 'toggleAutoTransition'].includes(String(type))) {
    checkExtraKeys(raw.action, ['type'], `${path}.action`, errors);
  } else {
    errors.push(`${path}.action.type is not recognized`);
  }
  return true;
}

function validateBindings(raw: unknown, path: string, errors: string[]): ControlBinding[] | undefined {
  if (raw === undefined) return undefined;
  if (!Array.isArray(raw)) {
    errors.push(`${path} must be an array`);
    return undefined;
  }
  if (raw.length > 100) errors.push(`${path} must contain at most 100 mappings`);
  raw.forEach((binding, index) => validateBinding(binding, `${path}[${index}]`, errors));
  const sanitized = sanitizeBindings(raw);
  if (sanitized.length !== raw.length) errors.push(`${path} contains malformed or duplicate mappings`);
  return sanitized;
}

function validateVjTimeline(raw: unknown, path: string, errors: string[]): VjTimeline | null {
  if (!isRecord(raw)) {
    errors.push(`${path} must be an object`);
    return null;
  }
  checkExtraKeys(raw, ['hz', 'durationMs', 'events'], path, errors);
  if (!isFiniteNumber(raw.hz) || raw.hz <= 0 || raw.hz > 120) errors.push(`${path}.hz must be greater than 0 and at most 120`);
  if (!isFiniteNumber(raw.durationMs) || raw.durationMs < 0) errors.push(`${path}.durationMs must be a non-negative number`);
  if (!Array.isArray(raw.events) || raw.events.length === 0 || raw.events.length > MAX_TIMELINE_EVENTS) {
    errors.push(`${path}.events must contain 1-${MAX_TIMELINE_EVENTS} events`);
    return null;
  }
  let lastT = 0;
  raw.events.forEach((event, index) => {
    const eventPath = `${path}.events[${index}]`;
    if (!isRecord(event)) {
      errors.push(`${eventPath} must be an object`);
      return;
    }
    const commonValid = isFiniteNumber(event.t)
      && event.t >= lastT
      && Number.isInteger(event.slot)
      && Number(event.slot) >= 0
      && Number(event.slot) < MAX_SHARED_SLOTS;
    if (!commonValid) errors.push(`${eventPath} has an invalid time or slot`);
    if (isFiniteNumber(event.t)) lastT = Math.max(lastT, event.t);
    if (event.kind === 'shader') {
      checkExtraKeys(event, ['t', 'slot', 'kind', 'value'], eventPath, errors);
      if (typeof event.value !== 'string' || !event.value || event.value.length > 128) {
        errors.push(`${eventPath}.value must be a shader id of at most 128 characters`);
      }
    } else if (event.kind === 'param') {
      checkExtraKeys(event, ['t', 'slot', 'kind', 'key', 'value'], eventPath, errors);
      if (typeof event.key !== 'string' || !TIMELINE_PARAM_KEYS.has(event.key) || !isFiniteNumber(event.value)) {
        errors.push(`${eventPath} has an invalid parameter key or value`);
      }
    } else {
      errors.push(`${eventPath}.kind is not recognized`);
    }
  });
  return raw as unknown as VjTimeline;
}

function validateVjSetExport(raw: unknown, errors: string[]): VjSetExportPayload | undefined {
  if (raw === undefined) return undefined;
  const path = 'project.timeline';
  if (!isRecord(raw)) {
    errors.push(`${path} must be a VJ set export object`);
    return undefined;
  }
  checkExtraKeys(raw, ['exportVersion', 'name', 'vibePrompt', 'savedAt', 'chain', 'chainString', 'bindings', 'timeline'], path, errors);
  if (raw.exportVersion !== 1) errors.push(`${path}.exportVersion must be 1`);
  if (typeof raw.name !== 'string' || !raw.name.trim()) errors.push(`${path}.name must be non-empty`);
  if (raw.vibePrompt !== undefined && typeof raw.vibePrompt !== 'string') errors.push(`${path}.vibePrompt must be a string`);
  if (!isFiniteNumber(raw.savedAt)) errors.push(`${path}.savedAt must be a finite number`);
  validateChain(raw.chain, `${path}.chain`, errors);
  if (typeof raw.chainString !== 'string' || !raw.chainString) errors.push(`${path}.chainString must be non-empty`);
  validateBindings(raw.bindings, `${path}.bindings`, errors);
  if (raw.timeline !== undefined) validateVjTimeline(raw.timeline, `${path}.timeline`, errors);
  if (errors.length > 0) return undefined;
  return parseVjSetExport(JSON.stringify(raw)) ?? undefined;
}

/** Validate and normalize a current-version project file without throwing. */
function validateModulation(raw: unknown, errors: string[]): Route[] {
  const path = 'project.modulation';
  if (!Array.isArray(raw)) {
    errors.push(`${path} must be an array`);
    return [];
  }
  if (raw.length > MAX_MODULATION_ROUTES) errors.push(`${path} must have at most ${MAX_MODULATION_ROUTES} routes`);
  const routes: Route[] = [];
  const ids = new Set<string>();
  raw.forEach((entry, i) => {
    const errs = routeErrors(entry, `${path}[${i}]`);
    if (errs.length === 0) {
      const route = toRoute(entry as Route);
      if (route.target.slot >= MAX_SHARED_SLOTS) errs.push(`${path}[${i}].target.slot must be below ${MAX_SHARED_SLOTS}`);
      if (ids.has(route.id)) errs.push(`${path}[${i}].id "${route.id}" is a duplicate`);
      ids.add(route.id);
      if (errs.length === 0) routes.push(route);
    }
    errors.push(...errs);
  });
  return routes;
}

export function validateProjectFile(raw: unknown): ProjectValidationResult {
  const errors: string[] = [];
  if (!isRecord(raw)) return { ok: false, errors: ['project must be an object'] };
  checkExtraKeys(raw, TOP_LEVEL_KEYS, 'project', errors);

  if (raw.schemaVersion !== PROJECT_FILE_SCHEMA_VERSION) {
    errors.push(`project.schemaVersion must be ${PROJECT_FILE_SCHEMA_VERSION}`);
  }

  let appVersion = '';
  if (!isRecord(raw.app)) {
    errors.push('project.app must be an object');
  } else {
    checkExtraKeys(raw.app, ['name', 'version'], 'project.app', errors);
    if (raw.app.name !== PROJECT_APP_NAME) errors.push(`project.app.name must be "${PROJECT_APP_NAME}"`);
    if (typeof raw.app.version !== 'string' || !raw.app.version.trim() || raw.app.version.length > 128) {
      errors.push('project.app.version must be a non-empty string of at most 128 characters');
    } else {
      appVersion = raw.app.version.trim();
    }
  }

  let createdAt = '';
  if (typeof raw.createdAt !== 'string' || !raw.createdAt.trim() || !Number.isFinite(Date.parse(raw.createdAt))) {
    errors.push('project.createdAt must be an ISO date-time string');
  } else {
    createdAt = raw.createdAt;
  }

  const chain = validateChain(raw.chain, 'project.chain', errors);
  if (!Number.isInteger(raw.activeSlot) || Number(raw.activeSlot) < 0 || Number(raw.activeSlot) >= MAX_SHARED_SLOTS) {
    errors.push(`project.activeSlot must be an integer from 0 to ${MAX_SHARED_SLOTS - 1}`);
  }
  const source = validateSource(raw.source, errors);

  const render: ProjectFile['render'] = {};
  if (raw.render === undefined) {
    errors.push('project.render must be an object');
  } else if (!isRecord(raw.render)) {
    errors.push('project.render must be an object');
  } else {
    checkExtraKeys(raw.render, ['renderScale', 'quality', 'hdr'], 'project.render', errors);
    if (raw.render.renderScale !== undefined) {
      if (!isFiniteNumber(raw.render.renderScale) || raw.render.renderScale < 0.25 || raw.render.renderScale > 1) {
        errors.push('project.render.renderScale must be between 0.25 and 1');
      } else {
        render.renderScale = raw.render.renderScale;
      }
    }
    if (raw.render.quality !== undefined) {
      if (typeof raw.render.quality !== 'string' || !QUALITY_MODES.has(raw.render.quality as RenderQualityMode)) {
        errors.push('project.render.quality is not recognized');
      } else {
        render.quality = raw.render.quality as RenderQualityMode;
      }
    }
    if (raw.render.hdr !== undefined) {
      const hdr = raw.render.hdr;
      const inRange = (v: unknown) => isFiniteNumber(v) && v >= HDR_NITS_RANGE.min && v <= HDR_NITS_RANGE.max;
      if (!isRecord(hdr)) {
        errors.push('project.render.hdr must be an object');
      } else {
        checkExtraKeys(hdr, ['paperWhiteNits', 'peakNits'], 'project.render.hdr', errors);
        if (!inRange(hdr.paperWhiteNits) || !inRange(hdr.peakNits)) {
          errors.push(`project.render.hdr paperWhiteNits / peakNits must be ${HDR_NITS_RANGE.min}–${HDR_NITS_RANGE.max}`);
        } else if ((hdr.peakNits as number) < (hdr.paperWhiteNits as number)) {
          errors.push('project.render.hdr.peakNits must be at least paperWhiteNits');
        } else {
          render.hdr = { paperWhiteNits: hdr.paperWhiteNits as number, peakNits: hdr.peakNits as number };
        }
      }
    }
  }

  let audio: ProjectFile['audio'];
  if (raw.audio !== undefined) {
    if (!isRecord(raw.audio)) {
      errors.push('project.audio must be an object');
    } else {
      checkExtraKeys(raw.audio, ['mappings'], 'project.audio', errors);
      const mappings = validateBindings(raw.audio.mappings, 'project.audio.mappings', errors);
      audio = mappings ? { mappings } : {};
    }
  }
  const timeline = validateVjSetExport(raw.timeline, errors);
  const modulation = validateModulation(raw.modulation, errors);

  if (errors.length > 0 || !chain || !source) return { ok: false, errors };
  const project: ProjectFile = {
    schemaVersion: PROJECT_FILE_SCHEMA_VERSION,
    app: { name: PROJECT_APP_NAME, version: appVersion },
    createdAt,
    chain,
    activeSlot: raw.activeSlot as number,
    source,
    render,
    ...(audio ? { audio } : {}),
    ...(timeline ? { timeline } : {}),
    modulation,
  };
  return { ok: true, project };
}
