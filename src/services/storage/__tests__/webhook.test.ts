import { requestUploadToken, webhookSave } from '../webhook';
import { StorageClient } from '../client';
import * as appConfig from '../../../config/appConfig';

const CONFIG = {
  webhookUrl: 'https://vps.example/webhook',
  staticUrl: 'https://static.example',
  apiUrl: 'https://api.example',
  shaderFilesBaseUrl: 'https://app.example/',
};

function jsonResponse(body: unknown, status = 200): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    json: async () => body,
    text: async () => JSON.stringify(body),
  } as unknown as Response;
}

describe('storage webhook auth (regression: HMAC secret shipped in the bundle)', () => {
  const realFetch = global.fetch;
  afterEach(() => {
    global.fetch = realFetch;
  });

  it('asks storage_manager for a scoped token, then sends it as a bearer token — no client signature', async () => {
    const fetchMock = vi.fn(async (url: string) =>
      url.endsWith('/upload-token')
        ? jsonResponse({ token: 'tok-123', expires_at: Date.now() + 60_000 })
        : jsonResponse({ success: true, files: ['image-effects/shaders/a.json'] }),
    );
    global.fetch = fetchMock as unknown as typeof fetch;

    const result = await webhookSave(CONFIG, { action: 'save_shader', name: 'a', data: { x: 1 } });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [tokenUrl, tokenInit] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(tokenUrl).toBe('https://vps.example/webhook/upload-token');
    expect(JSON.parse(tokenInit.body as string)).toEqual({ action: 'save_shader', name: 'a' });

    const [saveUrl, saveInit] = fetchMock.mock.calls[1] as unknown as [string, RequestInit];
    expect(saveUrl).toBe('https://vps.example/webhook/image-effects');
    const headers = saveInit.headers as Record<string, string>;
    expect(headers.Authorization).toBe('Bearer tok-123');
    expect(headers).not.toHaveProperty('X-Hub-Signature-256');
    expect(result.url).toBe('https://static.example/image-effects/shaders/a.json');
  });

  it('fails the save when no token is issued', async () => {
    global.fetch = vi.fn(async () => jsonResponse({})) as unknown as typeof fetch;
    await expect(requestUploadToken(CONFIG, { action: 'save_shader', name: 'a' })).rejects.toThrow(/no upload token/);
  });

  it('exposes no webhook secret from config or the client', () => {
    expect(Object.keys(appConfig)).not.toContain('STORAGE_WEBHOOK_SECRET');
    const client = new StorageClient() as unknown as { config: Record<string, unknown> };
    expect(client.config).not.toHaveProperty('secret');
  });
});
