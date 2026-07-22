import {
  normalizeShaderRatingResponse,
  postShaderRating,
} from './postShaderRating';

describe('postShaderRating', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('POSTs JSON { rating } (not FormData stars)', async () => {
    global.fetch = jest.fn(async () =>
      new Response(
        JSON.stringify({
          shader_id: 'glass-brick-distortion',
          rating: 5,
          has_errors: false,
          message: 'Rating updated successfully',
        }),
        { status: 200, headers: { 'content-type': 'application/json' } },
      ),
    ) as typeof fetch;

    const result = await postShaderRating(
      'https://storage.noahcohn.com',
      'glass-brick-distortion',
      5,
    );

    expect(global.fetch).toHaveBeenCalledWith(
      'https://storage.noahcohn.com/api/shaders/glass-brick-distortion/rate',
      expect.objectContaining({
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
      }),
    );
    const [, init] = (global.fetch as jest.Mock).mock.calls[0] as [string, RequestInit];
    expect(typeof init.body).toBe('string');
    expect(JSON.parse(String(init.body))).toEqual({ rating: 5 });
    expect(result).toEqual({
      id: 'glass-brick-distortion',
      stars: 5,
      rating_count: 0,
      your_rating: 5,
      has_errors: false,
      message: 'Rating updated successfully',
    });
  });

  it('includes notes and idempotency_key when provided', async () => {
    global.fetch = jest.fn(async () =>
      new Response(JSON.stringify({ rating: 4 }), { status: 200 }),
    ) as typeof fetch;

    await postShaderRating('https://storage.example.com/', 'liquid', 4, {
      notes: 'nice',
      idempotencyKey: 'abc123',
    });

    const [, init] = (global.fetch as jest.Mock).mock.calls[0] as [string, RequestInit];
    expect(JSON.parse(String(init.body))).toEqual({
      rating: 4,
      notes: 'nice',
      idempotency_key: 'abc123',
    });
  });

  it('rejects out-of-range ratings before fetch', async () => {
    global.fetch = jest.fn() as typeof fetch;
    await expect(postShaderRating('https://x', 'a', 9)).rejects.toThrow(/0 and 5/);
    expect(global.fetch).not.toHaveBeenCalled();
  });
});

describe('normalizeShaderRatingResponse', () => {
  it('maps live { shader_id, rating } payload', () => {
    expect(
      normalizeShaderRatingResponse('x', { shader_id: 'x', rating: 3 }, 3),
    ).toMatchObject({ id: 'x', stars: 3, your_rating: 3 });
  });

  it('maps legacy { id, stars, rating_count, your_rating } payload', () => {
    expect(
      normalizeShaderRatingResponse(
        'x',
        { id: 'x', stars: 4.2, rating_count: 10, your_rating: 5 },
        5,
      ),
    ).toEqual({
      id: 'x',
      stars: 4.2,
      rating_count: 10,
      your_rating: 5,
      has_errors: undefined,
      message: undefined,
    });
  });
});
