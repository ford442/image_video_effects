/**
 * draftHistory.ts
 *
 * Undo / redo for the Lab. Every draft edit is already a pure function that
 * returns a new draft (graphDraft.ts), so history is just a stack of draft
 * snapshots — no patches, no store library.
 *
 * Edits that carry the same `coalesce` key within COALESCE_MS (typing in a
 * field, dragging a node) fold into one undo step.
 */

export const HISTORY_LIMIT = 100;
export const COALESCE_MS = 600;

export interface DraftHistory<T> {
  past: T[];
  present: T;
  future: T[];
  /** Key + time of the last pushed edit, for coalescing. */
  lastKey: string | null;
  lastAt: number;
}

export function createHistory<T>(present: T): DraftHistory<T> {
  return { past: [], present, future: [], lastKey: null, lastAt: 0 };
}

export interface PushOptions {
  /** Fold into the previous step when it had the same key and was recent. */
  coalesce?: string;
  now?: number;
}

/** Record an edit. A no-op edit (same object) leaves history untouched. */
export function pushHistory<T>(h: DraftHistory<T>, next: T, opts: PushOptions = {}): DraftHistory<T> {
  if (next === h.present) return h;
  const now = opts.now ?? Date.now();
  const key = opts.coalesce ?? null;
  if (key !== null && key === h.lastKey && now - h.lastAt < COALESCE_MS) {
    return { ...h, present: next, future: [], lastAt: now };
  }
  const past = [...h.past, h.present];
  if (past.length > HISTORY_LIMIT) past.splice(0, past.length - HISTORY_LIMIT);
  return { past, present: next, future: [], lastKey: key, lastAt: now };
}

export function undo<T>(h: DraftHistory<T>): DraftHistory<T> {
  if (h.past.length === 0) return h;
  const past = h.past.slice(0, -1);
  const present = h.past[h.past.length - 1] as T;
  return { past, present, future: [h.present, ...h.future], lastKey: null, lastAt: 0 };
}

export function redo<T>(h: DraftHistory<T>): DraftHistory<T> {
  if (h.future.length === 0) return h;
  const [present, ...future] = h.future as [T, ...T[]];
  return { past: [...h.past, h.present], present, future, lastKey: null, lastAt: 0 };
}

export const canUndo = (h: DraftHistory<unknown>): boolean => h.past.length > 0;
export const canRedo = (h: DraftHistory<unknown>): boolean => h.future.length > 0;
