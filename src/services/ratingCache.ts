// ═══════════════════════════════════════════════════════════════════════════════
//  ratingCache.ts
//  Offline-first localStorage cache for shader star ratings.
//
//  Features:
//  - O(1) dirty index (px_dirty_list) so getDirtyRatings() avoids a linear scan
//  - Jittered exponential backoff + circuit breaker in flushDirtyRatings()
//  - X-Idempotency-Key header on sync POSTs so the server can deduplicate retries
// ═══════════════════════════════════════════════════════════════════════════════

const STORAGE_KEY_PREFIX = 'px_rating_';
const DIRTY_LIST_KEY = 'px_dirty_list';

// Circuit-breaker thresholds
const CB_FAILURE_THRESHOLD = 3;
const CB_COOLDOWN_BASE_MS = 30_000;   // 30 seconds base cooldown, doubles per tier
const CB_COOLDOWN_MAX_MS = 5 * 60_000; // 5 minutes cap

// Backoff config for jittered delays between reconnect retries (in initOfflineSync)
const RECONNECT_JITTER_MIN_MS = 200;
const RECONNECT_JITTER_MAX_MS = 1_800;
const BACKOFF_BASE_MS = 1_000;
const BACKOFF_CAP_MS = 30_000;

// Length (in chars) of the random suffix appended to idempotency keys.
// 7 base-36 chars give ~78 bits of randomness — enough to prevent accidental
// collision without storing a full UUID.
const IDEMPOTENCY_KEY_RANDOM_LENGTH = 7;

// ─── Public types ─────────────────────────────────────────────────────────────

export interface CachedRating {
  readonly rating: number;
  readonly dirty: boolean;
  readonly timestamp: number;
  /** Unique key sent as X-Idempotency-Key so the server can deduplicate retries. */
  readonly idempotencyKey: string;
}

// ─── Module-level circuit-breaker state ───────────────────────────────────────
// Exported for unit-testing only — consumers outside of tests must not mutate it.
export const circuitBreakerState = {
  consecutiveFailures: 0,
  openUntilMs: 0,
};

// ─── Private helpers ──────────────────────────────────────────────────────────

function storageKey(shaderId: string): string {
  return STORAGE_KEY_PREFIX + shaderId;
}

function getDirtySet(): Set<string> {
  try {
    const raw = localStorage.getItem(DIRTY_LIST_KEY);
    if (!raw) return new Set<string>();
    const parsed: unknown = JSON.parse(raw);
    if (Array.isArray(parsed)) return new Set<string>(parsed as string[]);
  } catch {
    // corrupted – start fresh
  }
  return new Set<string>();
}

function saveDirtySet(set: Set<string>): void {
  try {
    localStorage.setItem(DIRTY_LIST_KEY, JSON.stringify([...set]));
  } catch {
    // quota exceeded – best-effort
  }
}

function readEntry(shaderId: string): CachedRating | null {
  try {
    const raw = localStorage.getItem(storageKey(shaderId));
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (
      parsed !== null &&
      typeof parsed === 'object' &&
      typeof (parsed as Record<string, unknown>).rating === 'number' &&
      typeof (parsed as Record<string, unknown>).dirty === 'boolean' &&
      typeof (parsed as Record<string, unknown>).timestamp === 'number' &&
      typeof (parsed as Record<string, unknown>).idempotencyKey === 'string'
    ) {
      return parsed as CachedRating;
    }
  } catch {
    // corrupted entry – ignore
  }
  return null;
}

function writeEntry(shaderId: string, entry: CachedRating): void {
  try {
    localStorage.setItem(storageKey(shaderId), JSON.stringify(entry));
  } catch {
    // quota exceeded – best-effort
  }
}

function isCircuitOpen(): boolean {
  if (circuitBreakerState.openUntilMs === 0) return false;
  if (Date.now() >= circuitBreakerState.openUntilMs) {
    // Transition to half-open: reset the timer so one probe is allowed through
    circuitBreakerState.openUntilMs = 0;
    return false;
  }
  return true;
}

function recordSuccess(): void {
  circuitBreakerState.consecutiveFailures = 0;
  circuitBreakerState.openUntilMs = 0;
}

function recordFailure(): void {
  circuitBreakerState.consecutiveFailures += 1;
  if (circuitBreakerState.consecutiveFailures >= CB_FAILURE_THRESHOLD) {
    const tier = Math.floor(
      circuitBreakerState.consecutiveFailures / CB_FAILURE_THRESHOLD,
    );
    const cooldown = Math.min(
      CB_COOLDOWN_BASE_MS * Math.pow(2, tier - 1),
      CB_COOLDOWN_MAX_MS,
    );
    circuitBreakerState.openUntilMs = Date.now() + cooldown;
  }
}

/** Full-jitter backoff: uniform(0, min(cap, base * 2^retryCount)) */
function jitteredReconnectDelayMs(retryCount: number): number {
  if (retryCount === 0) {
    return RECONNECT_JITTER_MIN_MS + Math.random() * RECONNECT_JITTER_MAX_MS;
  }
  const exp = Math.min(BACKOFF_BASE_MS * Math.pow(2, retryCount), BACKOFF_CAP_MS);
  return Math.random() * exp;
}

// ─── Public API ───────────────────────────────────────────────────────────────

/**
 * Return the user's cached rating for a shader, or null if none is stored.
 */
export function getRating(shaderId: string): number | null {
  const entry = readEntry(shaderId);
  return entry !== null ? entry.rating : null;
}

/**
 * Persist a user rating to localStorage and mark it as dirty (pending sync).
 * Generates a fresh idempotency key so the server can deduplicate retries.
 */
export function setRating(shaderId: string, rating: number): void {
  const idempotencyKey =
    `${shaderId}-${Date.now()}-${Math.random().toString(36).slice(2, 2 + IDEMPOTENCY_KEY_RANDOM_LENGTH)}`;
  const entry: CachedRating = {
    rating,
    dirty: true,
    timestamp: Date.now(),
    idempotencyKey,
  };
  writeEntry(shaderId, entry);
  const dirty = getDirtySet();
  dirty.add(shaderId);
  saveDirtySet(dirty);
}

/**
 * Return all entries that have dirty=true.
 * O(1) via the px_dirty_list index — no full localStorage scan required.
 */
export function getDirtyRatings(): Record<string, CachedRating> {
  const dirtySet = getDirtySet();
  const result: Record<string, CachedRating> = {};
  for (const shaderId of dirtySet) {
    const entry = readEntry(shaderId);
    if (entry !== null && entry.dirty) {
      result[shaderId] = entry;
    }
  }
  return result;
}

/**
 * Mark a previously-dirty rating as synced (clean) and remove it from the
 * dirty index.  The rating value itself is preserved in localStorage.
 */
export function markSynced(shaderId: string): void {
  const entry = readEntry(shaderId);
  if (entry !== null) {
    writeEntry(shaderId, { ...entry, dirty: false });
  }
  const dirty = getDirtySet();
  dirty.delete(shaderId);
  saveDirtySet(dirty);
}

/**
 * Attempt to flush all dirty ratings to the API.
 *
 * - Skips silently if the circuit-breaker is open.
 * - Sends X-Idempotency-Key on every POST so the server can deduplicate retries.
 * - Consecutive failures open the circuit-breaker to prevent hammering a down backend.
 */
export async function flushDirtyRatings(apiUrl: string): Promise<void> {
  if (isCircuitOpen()) return;

  const dirty = getDirtyRatings();
  const shaderIds = Object.keys(dirty);
  if (shaderIds.length === 0) return;

  for (const shaderId of shaderIds) {
    if (isCircuitOpen()) break;

    const entry = dirty[shaderId];
    try {
      const formData = new FormData();
      formData.append('stars', entry.rating.toString());

      const response = await fetch(`${apiUrl}/api/shaders/${shaderId}/rate`, {
        method: 'POST',
        headers: { 'X-Idempotency-Key': entry.idempotencyKey },
        body: formData,
      });

      if (response.ok) {
        markSynced(shaderId);
        recordSuccess();
      } else {
        recordFailure();
      }
    } catch {
      recordFailure();
    }
  }
}

/**
 * Register a listener for the browser `online` event that flushes dirty ratings
 * after a small jittered delay (avoids thundering-herd when many clients
 * reconnect simultaneously).  Retries with exponential backoff if dirty entries
 * remain after a flush.
 *
 * Also initiates an immediate (jittered) flush if the browser is already online
 * at call time (covers the case of dirty entries left from a previous session).
 *
 * Returns an unsubscribe function that cancels pending timers and removes the
 * event listener.
 */
export function initOfflineSync(apiUrl: string): () => void {
  let retryCount = 0;
  let flushTimer: ReturnType<typeof setTimeout> | null = null;

  const scheduleFlush = (): void => {
    if (flushTimer !== null) clearTimeout(flushTimer);
    const delay = jitteredReconnectDelayMs(retryCount);
    flushTimer = setTimeout(() => {
      const dirtyCountBefore = Object.keys(getDirtyRatings()).length;
      if (dirtyCountBefore === 0) {
        retryCount = 0;
        return;
      }

      flushDirtyRatings(apiUrl)
        .then(() => {
          const dirtyCountAfter = Object.keys(getDirtyRatings()).length;
          if (dirtyCountAfter > 0 && navigator.onLine && !isCircuitOpen()) {
            // Some entries still dirty and backend seems reachable — retry
            retryCount += 1;
            scheduleFlush();
          } else {
            retryCount = 0;
          }
        })
        .catch((err: unknown) => {
          console.warn(
            `[ratingCache] flush error (dirty count: ${dirtyCountBefore}):`,
            err,
          );
        });
    }, delay);
  };

  const onOnline = (): void => {
    retryCount = 0;
    scheduleFlush();
  };

  window.addEventListener('online', onOnline);

  // Flush immediately if we already have dirty data and the browser is online
  if (navigator.onLine && Object.keys(getDirtyRatings()).length > 0) {
    scheduleFlush();
  }

  return (): void => {
    window.removeEventListener('online', onOnline);
    if (flushTimer !== null) clearTimeout(flushTimer);
  };
}
