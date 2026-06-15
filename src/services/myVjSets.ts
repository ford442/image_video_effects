// ═══════════════════════════════════════════════════════════════════════════════
//  myVjSets.ts
//  localStorage CRUD for user-saved "My VJ Sets": a named VJ stack persisted as
//  a shareable chain string plus its originating vibe prompt.
//
//  Separate storage key from the curated `preset_packs.json` and from
//  `vjPresets`/`vjHistory`. Mirrors the conventions in `vjPresets.ts`.
// ═══════════════════════════════════════════════════════════════════════════════

export interface MyVjSet {
  id: string;
  name: string;
  /** The vibe prompt that produced the stack (not embedded in `chainString`). */
  vibePrompt: string;
  /** URL-safe encoded SharedChain (from `encodeChain`). */
  chainString: string;
  savedAt: number;
}

const STORAGE_KEY = 'my_vj_sets';
const MAX_ENTRIES = 50;

export function saveMyVjSet(
  name: string,
  vibePrompt: string,
  chainString: string,
): MyVjSet {
  const sets = loadMyVjSets();
  const entry: MyVjSet = {
    id: crypto.randomUUID(),
    name: name.trim(),
    vibePrompt,
    chainString,
    savedAt: Date.now(),
  };
  sets.unshift(entry);
  if (sets.length > MAX_ENTRIES) {
    sets.length = MAX_ENTRIES;
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(sets));
  return entry;
}

export function loadMyVjSets(): MyVjSet[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed)) return [];
    return parsed;
  } catch {
    return [];
  }
}

export function deleteMyVjSet(id: string): void {
  const sets = loadMyVjSets().filter(s => s.id !== id);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(sets));
}
