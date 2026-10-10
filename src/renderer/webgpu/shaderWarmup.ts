/**
 * shaderWarmup.ts
 *
 * Idle-time pipeline warm-up for shaders the user is about to pick (#1314 WP-3).
 * The gallery reports what is on screen; this queue compiles those pipelines
 * with bounded concurrency so a click hits the pipeline cache instead of
 * stalling on createComputePipelineAsync. Warmed-but-unused pipelines live in
 * a small LRU so browsing 1,380 shaders cannot grow the cache without bound.
 */

export interface WarmupEntry {
  id: string;
  url: string;
}

export interface ShaderWarmupHost {
  /** Compile + cache; resolves true when the pipeline is ready. */
  load(entry: WarmupEntry): Promise<boolean>;
  isCached(id: string): boolean;
  /** Ids currently bound to a slot — never evicted. */
  boundIds(): Set<string>;
  evict(id: string): void;
  /** Skip shaders that must not be warmed (group-1 sim ring, fp32-pinned, deep-only, …). */
  canWarm?(id: string): boolean;
}

export interface ShaderWarmupOptions {
  concurrency?: number;
  lruSize?: number;
  /** Defer each job to idle time; defaults to requestIdleCallback / setTimeout. */
  schedule?: (job: () => void) => void;
}

const defaultSchedule = (job: () => void): void => {
  const ric = (globalThis as { requestIdleCallback?: (cb: () => void, opts?: { timeout: number }) => number })
    .requestIdleCallback;
  if (typeof ric === 'function') ric(job, { timeout: 500 });
  else setTimeout(job, 16);
};

export class ShaderWarmupQueue {
  private queue: WarmupEntry[] = [];
  private inFlight = new Set<string>();
  /** Warmed ids in least-recently-requested order (oldest first). */
  private warmed: string[] = [];
  private generation = 0;
  private stopped = false;
  private readonly concurrency: number;
  private readonly lruSize: number;
  private readonly schedule: (job: () => void) => void;

  constructor(private readonly host: ShaderWarmupHost, options: ShaderWarmupOptions = {}) {
    this.concurrency = Math.max(1, options.concurrency ?? 2);
    this.lruSize = Math.max(1, options.lruSize ?? 24);
    this.schedule = options.schedule ?? defaultSchedule;
  }

  /** Replace the pending queue with `entries` (most important first). */
  request(entries: WarmupEntry[]): void {
    if (this.stopped) return;
    this.generation++;
    const seen = new Set<string>();
    this.queue = entries.filter((e) => {
      if (!e.id || !e.url || seen.has(e.id)) return false;
      seen.add(e.id);
      if (this.host.isCached(e.id)) {
        this.touch(e.id);
        return false;
      }
      return !this.inFlight.has(e.id) && (this.host.canWarm?.(e.id) ?? true);
    });
    this.pump();
  }

  /** Stop and forget everything (device loss / renderer teardown). */
  stop(): void {
    this.stopped = true;
    this.generation++;
    this.queue = [];
    this.warmed = [];
  }

  get pending(): number {
    return this.queue.length + this.inFlight.size;
  }

  warmedIds(): string[] {
    return [...this.warmed];
  }

  private pump(): void {
    while (!this.stopped && this.inFlight.size < this.concurrency) {
      const entry = this.queue.shift();
      if (!entry) break;
      const generation = this.generation;
      this.inFlight.add(entry.id);
      this.schedule(() => {
        if (this.stopped || generation !== this.generation || this.host.isCached(entry.id)) {
          this.inFlight.delete(entry.id);
          if (!this.stopped && this.host.isCached(entry.id)) this.touch(entry.id);
          this.pump();
          return;
        }
        this.host
          .load(entry)
          .then((ok) => {
            if (ok && !this.stopped) this.touch(entry.id);
          })
          .catch(() => undefined)
          .finally(() => {
            this.inFlight.delete(entry.id);
            this.pump();
          });
      });
    }
  }

  private touch(id: string): void {
    this.warmed = this.warmed.filter((w) => w !== id);
    this.warmed.push(id);
    const bound = this.host.boundIds();
    while (this.warmed.length > this.lruSize) {
      const victimIndex = this.warmed.findIndex((w) => !bound.has(w));
      if (victimIndex < 0) break;
      const [victim] = this.warmed.splice(victimIndex, 1);
      if (victim !== undefined) this.host.evict(victim);
    }
  }
}
