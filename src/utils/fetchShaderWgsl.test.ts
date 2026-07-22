import { fetchShaderWgsl } from './fetchShaderWgsl';

describe('fetchShaderWgsl', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('returns WGSL from storage API JSON when static host 404s', async () => {
    global.fetch = jest.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('test.1ink.us')) {
        return new Response('not found', { status: 404 });
      }
      if (url.includes('/api/shaders/gen-fireworks-nocturne/code')) {
        return new Response(JSON.stringify({ code: '@compute fn main() {}' }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      }
      if (url.endsWith('./shaders/gen-fireworks-nocturne.wgsl')) {
        return new Response('not found', { status: 404 });
      }
      return new Response('not found', { status: 404 });
    }) as typeof fetch;

    const code = await fetchShaderWgsl(
      'gen-fireworks-nocturne',
      'https://test.1ink.us/image_video_effects/shaders/gen-fireworks-nocturne.wgsl'
    );

    expect(code).toBe('@compute fn main() {}');
  });

  it('prefers same-origin public shader before remote hosts', async () => {
    global.fetch = jest.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.endsWith('./shaders/liquid.wgsl')) {
        return new Response('@compute fn main() { /* local */ }', { status: 200 });
      }
      return new Response('remote', { status: 200 });
    }) as typeof fetch;

    const code = await fetchShaderWgsl('liquid', 'shaders/liquid.wgsl');
    expect(code).toContain('local');
  });

  it('primaryOnly skips storage API fallback for optional probes', async () => {
    const fetchMock = jest.fn(async (input: RequestInfo | URL) => {
      const url = String(input);
      if (url.includes('/api/shaders/')) {
        return new Response(JSON.stringify({ code: 'should-not-reach' }), {
          status: 200,
          headers: { 'content-type': 'application/json' },
        });
      }
      return new Response('not found', { status: 404 });
    });
    global.fetch = fetchMock as typeof fetch;

    const code = await fetchShaderWgsl(
      'motion-heatmap-sg',
      'shaders/motion-heatmap-sg.wgsl',
      { primaryOnly: true },
    );

    expect(code).toBeNull();
    const urls = fetchMock.mock.calls.map((c) => String(c[0]));
    expect(urls.some((u) => u.includes('/api/shaders/'))).toBe(false);
    expect(urls.some((u) => u.includes('storage.noahcohn.com'))).toBe(false);
  });
});
