import type { ShaderEntry } from '../../renderer/types';

const tokens = (query: string): string[] => query.toLowerCase().split(/\s+/).filter(Boolean);

/** True when every whitespace-separated token of `query` appears in `haystack`. */
export function matchesQuery(query: string, haystack: string): boolean {
    const t = tokens(query);
    if (t.length === 0) return true;
    const h = haystack.toLowerCase();
    return t.every((tok) => h.includes(tok));
}

/** Effects whose id / name / tags match the query, name-prefix matches first. */
export function findEffects(availableModes: ShaderEntry[], query: string, limit = 8): ShaderEntry[] {
    const t = tokens(query);
    if (t.length === 0) return [];
    const hits: Array<{ entry: ShaderEntry; rank: number }> = [];
    for (const entry of availableModes) {
        const name = entry.name.toLowerCase();
        const hay = `${entry.id} ${entry.name} ${(entry.tags ?? []).join(' ')}`;
        if (!matchesQuery(query, hay)) continue;
        hits.push({ entry, rank: name.startsWith(t[0] ?? '') ? 0 : 1 });
    }
    hits.sort((a, b) => a.rank - b.rank || a.entry.name.localeCompare(b.entry.name));
    return hits.slice(0, limit).map((h) => h.entry);
}
