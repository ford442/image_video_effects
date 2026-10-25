import { webhookSave } from '../webhook';
import { StorageHttpError } from '../http';
import type { StorageClientConfig } from '../types';

const CONFIG: StorageClientConfig = {
  webhookUrl: 'https://storage.example/api/webhook-proxy',
  staticUrl: 'https://static.example',
  apiUrl: 'https://storage.example',
  shaderFilesBaseUrl: 'https://cdn.example/',
};

afterEach(() => vi.unstubAllGlobals());

describe('webhookSave via the signing proxy (#1511 bug 2)', () => {
  it('POSTs the unsigned payload to the proxy and resolves the static url', async () => {
    const fetchMock = vi.fn(async () =>
      new Response(JSON.stringify({ status: 'success', files: ['image-effects/shaders/a.wgsl'] }), { status: 200 }),
    );
    vi.stubGlobal('fetch', fetchMock);

    const result = await webhookSave(CONFIG, { action: 'save_shader', name: 'a', data: { x: 1 } });

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe('https://storage.example/api/webhook-proxy/image-effects');
    expect(init.headers).toEqual({ 'Content-Type': 'application/json' });
    expect(JSON.parse(init.body as string)).toMatchObject({ action: 'save_shader', name: 'a', data: { x: 1 } });
    expect(result.url).toBe('https://static.example/image-effects/shaders/a.wgsl');
  });

  it("surfaces the proxy's error body on non-2xx", async () => {
    vi.stubGlobal('fetch', vi.fn(async () =>
      new Response('{"detail":"Webhook proxy is not configured"}', { status: 503, statusText: 'Service Unavailable' }),
    ));

    const err = await webhookSave(CONFIG, { action: 'save_shader', name: 'a', data: {} }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(StorageHttpError);
    expect(String((err as Error).message)).toContain('Webhook proxy is not configured');
  });
});
