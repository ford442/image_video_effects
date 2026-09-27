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
    const urls: string[] = [];
    global.fetch = jest.fn(async (input: RequestInfo | URL) => {
      urls.push(String(input));
      return new Response('not found', { status: 404 });
    }) as typeof fetch;

    const code = await fetchShaderWgsl(
      'motion-heatmap-sg',
      'shaders/motion-heatmap-sg.wgsl',
      { primaryOnly: true },
    );

    expect(code).toBeNull();
    expect(urls.some((u) => u.includes('/api/shaders/'))).toBe(false);
    expect(urls.some((u) => u.includes('storage.noahcohn.com'))).toBe(false);
  });

  describe('#include expansion', () => {
    it('expands a prelude include before returning', async () => {
      global.fetch = jest.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith('./shaders/zz-includes.wgsl')) {
          return new Response('#include "_prelude.wgsl"\n@compute fn main() {}', { status: 200 });
        }
        if (url.endsWith('./shaders/_prelude.wgsl')) {
          return new Response('@group(0) @binding(0) var u_sampler: sampler;', { status: 200 });
        }
        return new Response('not found', { status: 404 });
      }) as typeof fetch;

      const code = await fetchShaderWgsl('zz-includes');

      expect(code).toContain('@group(0) @binding(0) var u_sampler: sampler;');
      expect(code).toContain('@compute fn main() {}');
      expect(code).not.toContain('#include "_prelude.wgsl"');
    });

    it('resolves the library next to the shader it was served from', async () => {
      const urls: string[] = [];
      global.fetch = jest.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        urls.push(url);
        if (url === 'https://cdn.example/shaders/zz-cdn.wgsl') {
          return new Response('#include "_prelude.wgsl"\nfn main() {}', { status: 200 });
        }
        if (url === 'https://cdn.example/shaders/_prelude.wgsl') {
          return new Response('fn prelude() {}', { status: 200 });
        }
        return new Response('not found', { status: 404 });
      }) as typeof fetch;

      const code = await fetchShaderWgsl('zz-cdn', 'https://cdn.example/shaders/zz-cdn.wgsl');

      // The library must come from the CDN the shader came from, not same-origin.
      expect(code).toContain('fn prelude() {}');
      expect(urls).toContain('https://cdn.example/shaders/_prelude.wgsl');
    });

    it('returns null rather than unexpanded source when a library is missing', async () => {
      const error = jest.spyOn(console, 'error').mockImplementation(() => {});
      global.fetch = jest.fn(async (input: RequestInfo | URL) => {
        const url = String(input);
        if (url.endsWith('./shaders/zz-broken-include.wgsl')) {
          return new Response('#include "_nope.wgsl"\nfn main() {}', { status: 200 });
        }
        return new Response('not found', { status: 404 });
      }) as typeof fetch;

      await expect(fetchShaderWgsl('zz-broken-include')).resolves.toBeNull();
      expect(error).toHaveBeenCalledWith(expect.stringContaining('file not found'));
      error.mockRestore();
    });

    it('leaves a shader with no directive untouched', async () => {
      const source = '@group(0) @binding(0) var s: sampler;\n@compute fn main() {}';
      global.fetch = jest.fn(async () => new Response(source, { status: 200 })) as typeof fetch;

      await expect(fetchShaderWgsl('zz-plain')).resolves.toBe(source);
    });
  });
});
