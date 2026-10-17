/**
 * pipelineCache.ts
 *
 * Recency tracking for the compiled compute pipelines held by
 * WebGPUShaderManager. Every pipeline that is not bound to a slot (warm-up
 * prefetches and shaders the user browsed past) goes through this one LRU, so
 * browsing the 1,400-shader catalog cannot grow the cache without bound.
 */

/** Most compiled pipelines kept before the least recently used unbound ones are evicted. */
export const PIPELINE_CACHE_LIMIT = 32;

export class PipelineLru {
  /** Oldest first: a Set iterates in insertion order, so touch = delete + add. */
  private readonly order = new Set<string>();

  get size(): number {
    return this.order.size;
  }

  touch(id: string): void {
    this.order.delete(id);
    this.order.add(id);
  }

  remove(id: string): void {
    this.order.delete(id);
  }

  clear(): void {
    this.order.clear();
  }

  /** Ids oldest first. */
  ids(): string[] {
    return [...this.order];
  }

  /**
   * The ids to evict so at most `limit` remain: oldest first, skipping
   * `protectedIds` (slot-bound pipelines). Protected ids may keep the cache
   * above `limit`; they are never returned.
   */
  overflow(limit: number, protectedIds: ReadonlySet<string>): string[] {
    const victims: string[] = [];
    let remaining = this.order.size;
    for (const id of this.order) {
      if (remaining <= limit) break;
      if (protectedIds.has(id)) continue;
      victims.push(id);
      remaining--;
    }
    return victims;
  }
}
