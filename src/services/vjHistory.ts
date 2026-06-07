export interface VJHistoryEntry {
  id: string;
  vibeText: string;
  shaderIds: string[];
  params: Record<string, number>[];
  timestamp: number;
}

const STORAGE_KEY = 'vj_history';
const MAX_ENTRIES = 20;

export function saveVJStack(entry: Omit<VJHistoryEntry, 'id' | 'timestamp'>): VJHistoryEntry {
  const history = loadVJHistory();
  const newEntry: VJHistoryEntry = {
    ...entry,
    id: crypto.randomUUID(),
    timestamp: Date.now(),
  };
  history.unshift(newEntry);
  if (history.length > MAX_ENTRIES) {
    history.length = MAX_ENTRIES;
  }
  localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
  return newEntry;
}

export function loadVJHistory(): VJHistoryEntry[] {
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

export function clearVJHistory(): void {
  localStorage.removeItem(STORAGE_KEY);
}

export function removeVJEntry(id: string): void {
  const history = loadVJHistory().filter(e => e.id !== id);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
}
