import {
  getRating,
  setRating,
  getDirtyRatings,
  markSynced,
  flushDirtyRatings,
  initOfflineSync,
  _circuitBreaker,
} from './ratingCache';

const API_URL = 'https://storage.noahcohn.com';

describe('ratingCache', () => {
  const fetchMock = jest.fn();

  beforeEach(() => {
    localStorage.clear();
    _circuitBreaker.consecutiveFailures = 0;
    _circuitBreaker.openUntilMs = 0;
    fetchMock.mockReset();
    global.fetch = fetchMock as unknown as typeof fetch;
    jest.spyOn(console, 'warn').mockImplementation(() => undefined);
  });

  afterEach(() => {
    jest.restoreAllMocks();
  });

  // ─── getRating / setRating ─────────────────────────────────────────────────

  describe('getRating', () => {
    it('returns null for an unrated shader', () => {
      expect(getRating('unknown-shader')).toBeNull();
    });

    it('returns the stored rating value', () => {
      setRating('my-shader', 4);
      expect(getRating('my-shader')).toBe(4);
    });

    it('returns null when localStorage contains corrupted data', () => {
      localStorage.setItem('px_rating_bad-shader', 'not-json{{{');
      expect(getRating('bad-shader')).toBeNull();
    });
  });

  // ─── getDirtyRatings ───────────────────────────────────────────────────────

  describe('getDirtyRatings', () => {
    it('returns empty object when nothing is stored', () => {
      expect(getDirtyRatings()).toEqual({});
    });

    it('returns all dirty entries after setRating calls', () => {
      setRating('shader-a', 3);
      setRating('shader-b', 5);
      const dirty = getDirtyRatings();
      expect(Object.keys(dirty).sort()).toEqual(['shader-a', 'shader-b']);
      expect(dirty['shader-a'].rating).toBe(3);
      expect(dirty['shader-b'].rating).toBe(5);
      expect(dirty['shader-a'].dirty).toBe(true);
    });

    it('does not return clean entries', () => {
      setRating('shader-a', 3);
      markSynced('shader-a');
      expect(getDirtyRatings()).toEqual({});
    });

    it('includes an idempotencyKey in each entry', () => {
      setRating('shader-a', 4);
      const dirty = getDirtyRatings();
      expect(typeof dirty['shader-a'].idempotencyKey).toBe('string');
      expect(dirty['shader-a'].idempotencyKey.length).toBeGreaterThan(0);
    });
  });

  // ─── markSynced ───────────────────────────────────────────────────────────

  describe('markSynced', () => {
    it('removes the shader from the dirty list', () => {
      setRating('shader-a', 3);
      markSynced('shader-a');
      expect(getDirtyRatings()).toEqual({});
    });

    it('preserves the rating value after marking synced', () => {
      setRating('shader-a', 3);
      markSynced('shader-a');
      expect(getRating('shader-a')).toBe(3);
    });

    it('is safe to call on a shader that was never rated', () => {
      expect(() => markSynced('nonexistent')).not.toThrow();
    });
  });

  // ─── flushDirtyRatings ────────────────────────────────────────────────────

  describe('flushDirtyRatings', () => {
    it('does nothing when there are no dirty ratings', async () => {
      await flushDirtyRatings(API_URL);
      expect(fetchMock).not.toHaveBeenCalled();
    });

    it('POSTs dirty ratings to the correct endpoint', async () => {
      setRating('shader-a', 4);
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ id: 'shader-a', stars: 4, rating_count: 1 }),
      });

      await flushDirtyRatings(API_URL);

      expect(fetchMock).toHaveBeenCalledWith(
        `${API_URL}/api/shaders/shader-a/rate`,
        expect.objectContaining({ method: 'POST' }),
      );
    });

    it('includes X-Idempotency-Key header in the POST', async () => {
      setRating('shader-a', 4);
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ id: 'shader-a', stars: 4, rating_count: 1 }),
      });

      await flushDirtyRatings(API_URL);

      expect(fetchMock).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({
          headers: expect.objectContaining({
            'X-Idempotency-Key': expect.any(String),
          }),
        }),
      );
    });

    it('marks ratings as synced after a successful POST', async () => {
      setRating('shader-a', 4);
      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ id: 'shader-a', stars: 4, rating_count: 1 }),
      });

      await flushDirtyRatings(API_URL);

      expect(getDirtyRatings()).toEqual({});
    });

    it('leaves ratings dirty when the POST returns a non-OK status', async () => {
      setRating('shader-a', 4);
      fetchMock.mockResolvedValueOnce({ ok: false, status: 503 });

      await flushDirtyRatings(API_URL);

      expect(getDirtyRatings()['shader-a']).toBeDefined();
    });

    it('leaves ratings dirty when the network request throws', async () => {
      setRating('shader-a', 4);
      fetchMock.mockRejectedValueOnce(new Error('network error'));

      await flushDirtyRatings(API_URL);

      expect(getDirtyRatings()['shader-a']).toBeDefined();
    });

    it('skips the flush entirely when the circuit breaker is open', async () => {
      setRating('shader-a', 4);
      _circuitBreaker.openUntilMs = Date.now() + 60_000;

      await flushDirtyRatings(API_URL);

      expect(fetchMock).not.toHaveBeenCalled();
    });

    it('opens the circuit breaker after consecutive failures', async () => {
      // CB_FAILURE_THRESHOLD = 3 — three consecutive failures open the breaker
      setRating('shader-a', 4);
      setRating('shader-b', 3);
      setRating('shader-c', 5);

      fetchMock.mockRejectedValue(new Error('network error'));

      // One flush processes all three shaders, recording three failures
      await flushDirtyRatings(API_URL);

      expect(_circuitBreaker.openUntilMs).toBeGreaterThan(Date.now());
    });

    it('resets the circuit breaker after a successful flush', async () => {
      setRating('shader-a', 4);
      // Simulate an earlier failure that hasn't yet tripped the breaker
      _circuitBreaker.consecutiveFailures = 2;

      fetchMock.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ id: 'shader-a', stars: 4, rating_count: 1 }),
      });

      await flushDirtyRatings(API_URL);

      expect(_circuitBreaker.consecutiveFailures).toBe(0);
      expect(_circuitBreaker.openUntilMs).toBe(0);
    });

    it('flushes multiple dirty shaders in one call', async () => {
      setRating('shader-a', 4);
      setRating('shader-b', 2);

      fetchMock
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ id: 'shader-a', stars: 4, rating_count: 1 }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ id: 'shader-b', stars: 2, rating_count: 1 }),
        });

      await flushDirtyRatings(API_URL);

      expect(fetchMock).toHaveBeenCalledTimes(2);
      expect(getDirtyRatings()).toEqual({});
    });
  });

  // ─── initOfflineSync ──────────────────────────────────────────────────────

  describe('initOfflineSync', () => {
    beforeEach(() => {
      jest.useFakeTimers();
    });

    afterEach(() => {
      jest.useRealTimers();
    });

    it('returns a cleanup function', () => {
      const cleanup = initOfflineSync(API_URL);
      expect(typeof cleanup).toBe('function');
      cleanup();
    });

    it('schedules a flush when the online event fires and there are dirty ratings', () => {
      setRating('shader-a', 4);
      fetchMock.mockResolvedValue({
        ok: true,
        json: async () => ({ id: 'shader-a', stars: 4, rating_count: 1 }),
      });

      const cleanup = initOfflineSync(API_URL);

      window.dispatchEvent(new Event('online'));
      jest.runAllTimers();

      cleanup();
      // fetch was eventually called (timers ran)
      expect(fetchMock).toHaveBeenCalled();
    });

    it('removes the online listener when the cleanup function is called', () => {
      const removeSpy = jest.spyOn(window, 'removeEventListener');
      const cleanup = initOfflineSync(API_URL);
      cleanup();
      expect(removeSpy).toHaveBeenCalledWith('online', expect.any(Function));
    });
  });
});
