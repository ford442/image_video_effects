import {
  StorageHttpError,
  encodeResourcePath,
  mapHttpError,
  resolveStaticUrl,
  unwrapListResponse,
} from '../http';

describe('storage/http', () => {
  describe('encodeResourcePath', () => {
    it('encodes spaces and special characters in path segments', () => {
      expect(encodeResourcePath('neon pulse')).toBe('neon%20pulse');
      expect(encodeResourcePath('shader/with/slash')).toBe('shader%2Fwith%2Fslash');
      expect(encodeResourcePath('café-shader')).toBe('caf%C3%A9-shader');
    });

    it('trims whitespace before encoding', () => {
      expect(encodeResourcePath('  liquid-chrome  ')).toBe('liquid-chrome');
    });
  });

  describe('resolveStaticUrl', () => {
    it('joins base and relative path without duplicate slashes', () => {
      expect(resolveStaticUrl('https://storage.example.com/', 'image-effects/shaders/foo.json'))
        .toBe('https://storage.example.com/image-effects/shaders/foo.json');
      expect(resolveStaticUrl('https://storage.example.com', '/metadata/preset.json'))
        .toBe('https://storage.example.com/metadata/preset.json');
    });

    it('returns absolute URLs unchanged', () => {
      const url = 'https://cdn.example.com/shaders/liquid.wgsl';
      expect(resolveStaticUrl('https://storage.example.com', url)).toBe(url);
    });
  });

  describe('mapHttpError', () => {
    it('maps response status and body to StorageHttpError', async () => {
      const response = new Response('Shader not found', {
        status: 404,
        statusText: 'Not Found',
      });
      const error = await mapHttpError(response);
      expect(error).toBeInstanceOf(StorageHttpError);
      expect(error.status).toBe(404);
      expect(error.statusText).toBe('Not Found');
      expect(error.message).toContain('404');
      expect(error.message).toContain('Shader not found');
      expect(error.body).toBe('Shader not found');
    });

    it('handles empty error bodies', async () => {
      const response = new Response('', { status: 500, statusText: 'Internal Server Error' });
      const error = await mapHttpError(response);
      expect(error.message).toBe('HTTP 500 Internal Server Error');
    });
  });

  describe('unwrapListResponse', () => {
    it('returns bare arrays as-is', () => {
      const data = [{ id: 'a' }, { id: 'b' }];
      expect(unwrapListResponse(data, 'shaders')).toEqual(data);
    });

    it('unwraps keyed object responses', () => {
      const data = { shaders: [{ id: 'liquid' }] };
      expect(unwrapListResponse(data, 'shaders')).toEqual([{ id: 'liquid' }]);
    });

    it('throws on invalid shapes', () => {
      expect(() => unwrapListResponse({ ok: true }, 'shaders')).toThrow(/Invalid response format/);
    });
  });
});
