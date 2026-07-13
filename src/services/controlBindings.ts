// ═══════════════════════════════════════════════════════════════════════════════
//  controlBindings.ts
//  Live-performance control bindings for MIDI CC, MIDI note, and keyboard keys.
//  Pure registry + dispatcher; hardware adapters produce normalized ControlEvents.
// ═══════════════════════════════════════════════════════════════════════════════

export type ControlSource = 'midi-cc' | 'midi-note' | 'key';

export type ControlEventCallback = (event: ControlEvent) => void;

export interface ControlEvent {
  source: ControlSource;
  id: string;
  value: number; // normalized 0..1
}

export interface ControlTrigger {
  source: ControlSource;
  id: string;
}

export type ControlAction =
  | { type: 'setSlotParam'; slot: number; param: string }
  | { type: 'randomizeSlot'; slot: number }
  | { type: 'randomizeAll' }
  | { type: 'triggerTransition' }
  | { type: 'toggleAutoTransition' };

export interface ControlBinding {
  trigger: ControlTrigger;
  action: ControlAction;
}

/**
 * Handle passed to the dispatcher. The control surface wires these to the live
 * app/Alucinate callbacks WITHOUT forking AutoDJ.ts (read-only for this track).
 */
export interface LiveActionsHandle {
  setSlotParam: (slot: number, param: string, value: number) => void;
  randomizeSlot: (slot: number) => void;
  randomizeAll: () => void;
  triggerTransition: () => void;
  toggleAutoTransition: () => void;
}

const STORAGE_KEY = 'vj_control_bindings';
const MAX_ENTRIES = 100;

function triggerKey(trigger: ControlTrigger): string {
  return `${trigger.source}::${trigger.id}`;
}

export function makeTrigger(source: ControlSource, id: string): ControlTrigger {
  return { source, id };
}

export class ControlBindingRegistry {
  private bindings = new Map<string, ControlBinding>();

  constructor(initial: ControlBinding[] = []) {
    for (const binding of initial) {
      this.addBinding(binding.trigger, binding.action);
    }
  }

  addBinding(trigger: ControlTrigger, action: ControlAction): ControlBinding {
    const binding: ControlBinding = { trigger, action };
    this.bindings.set(triggerKey(trigger), binding);
    return binding;
  }

  removeBinding(trigger: ControlTrigger): boolean {
    return this.bindings.delete(triggerKey(trigger));
  }

  getBindings(): ControlBinding[] {
    return Array.from(this.bindings.values());
  }

  clear(): void {
    this.bindings.clear();
  }

  dispatch(event: ControlEvent, handle: LiveActionsHandle): boolean {
    const binding = this.bindings.get(triggerKey(event));
    if (!binding) return false;

    const { action } = binding;
    switch (action.type) {
      case 'setSlotParam':
        handle.setSlotParam(action.slot, action.param, event.value);
        break;
      case 'randomizeSlot':
        // Trigger on press / non-zero value to avoid repeating while a key is held.
        if (event.value > 0) {
          handle.randomizeSlot(action.slot);
        }
        break;
      case 'randomizeAll':
        if (event.value > 0) {
          handle.randomizeAll();
        }
        break;
      case 'triggerTransition':
        if (event.value > 0) {
          handle.triggerTransition();
        }
        break;
      case 'toggleAutoTransition':
        if (event.value > 0) {
          handle.toggleAutoTransition();
        }
        break;
      default:
        return false;
    }
    return true;
  }

  serialize(): string {
    return JSON.stringify(this.getBindings());
  }

  static deserialize(raw: string): ControlBinding[] {
    try {
      const parsed = JSON.parse(raw);
      if (!Array.isArray(parsed)) return [];
      return parsed.filter(isValidControlBinding);
    } catch {
      return [];
    }
  }
}

export function loadBindings(): ControlBinding[] {
  if (typeof localStorage === 'undefined') return [];
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    return ControlBindingRegistry.deserialize(raw);
  } catch {
    return [];
  }
}

export function saveBindings(bindings: ControlBinding[]): void {
  if (typeof localStorage === 'undefined') return;
  const capped = bindings.slice(0, MAX_ENTRIES);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(capped));
}

function isValidControlBinding(value: unknown): value is ControlBinding {
  if (!value || typeof value !== 'object') return false;
  const b = value as Partial<ControlBinding>;
  if (!b.trigger || typeof b.trigger !== 'object') return false;
  if (!b.action || typeof b.action !== 'object') return false;

  const trigger = b.trigger as Partial<ControlTrigger>;
  if (!trigger.source || !trigger.id) return false;
  if (!['midi-cc', 'midi-note', 'key'].includes(trigger.source)) return false;

  const action = b.action as Partial<ControlAction>;
  if (!action.type) return false;
  switch (action.type) {
    case 'setSlotParam':
      return typeof action.slot === 'number' && typeof action.param === 'string';
    case 'randomizeSlot':
      return typeof action.slot === 'number';
    case 'randomizeAll':
    case 'triggerTransition':
    case 'toggleAutoTransition':
      return true;
    default:
      return false;
  }
}
