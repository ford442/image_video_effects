/** Weight for shaders that have a preview thumbnail in attract/roulette selection. */
export const THUMBNAIL_PICK_WEIGHT = 3;

/**
 * Pick one item from a list using optional per-item weights.
 */
export function pickWeighted<T>(items: T[], weightFn: (item: T) => number): T | null {
  if (items.length === 0) return null;
  const weights = items.map(weightFn);
  const total = weights.reduce((sum, w) => sum + w, 0);
  if (total <= 0) {
    return items[Math.floor(Math.random() * items.length)];
  }
  let roll = Math.random() * total;
  for (let i = 0; i < items.length; i++) {
    roll -= weights[i];
    if (roll <= 0) return items[i];
  }
  return items[items.length - 1];
}

/**
 * Weighted random shader id pick — thumbed shaders preferred.
 */
export function pickWeightedShaderId(
  ids: string[],
  hasThumbnail: (id: string) => boolean,
  thumbWeight = THUMBNAIL_PICK_WEIGHT,
): string | null {
  if (ids.length === 0) return null;
  const picked = pickWeighted(ids, id => (hasThumbnail(id) ? thumbWeight : 1));
  return picked ?? null;
}

/**
 * Weighted random shader entry from a list.
 */
export function pickWeightedShader<T extends { id: string }>(
  items: T[],
  hasThumbnail: (id: string) => boolean,
  thumbWeight = THUMBNAIL_PICK_WEIGHT,
): T | null {
  if (items.length === 0) return null;
  return pickWeighted(items, item => (hasThumbnail(item.id) ? thumbWeight : 1));
}
