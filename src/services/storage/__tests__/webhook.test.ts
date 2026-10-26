/**
 * The webhook HMAC secret must never live in the client: webhookSave asks the storage_manager
 * signer for the signature of the exact body it then posts.
 */
import { webhookSave } from '../webhook';
import type { StorageClientConfig } from '../types';

const config: StorageClientConfig = {
  webhookUrl: 'https://vps.test/webhook',
  staticUrl: 'https://static.test',
  signUrl: 'https://vps.test/api/storage/sign-webhook',
  apiUrl: 'https://vps.test',
  shaderFilesBaseUrl: 'https://cdn.test/',
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

describe('webhookSave', () => {
  afterEach(() => vi.unstubAllGlobals());

  it('signs server-side and posts the identical body with that signature', async () => {
    const fetchMock = vi.fn()
      .mockResolvedValueOnce(jsonResponse({ signature: 'sha256=abc' }))
      .mockResolvedValueOnce(jsonResponse({ status: 'success', files: ['image-effects/shaders/x.wgsl'] }));
    vi.stubGlobal('fetch', fetchMock);

    const result = await webhookSave(config, { action: 'save_shader', name: 'x', data: { a: 1 } });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    const [signUrl, signInit] = fetchMock.mock.calls[0] as [string, RequestInit];
    const [hookUrl, hookInit] = fetchMock.mock.calls[1] as [string, RequestInit];
    expect(signUrl).toBe(config.signUrl);
    expect(hookUrl).toBe('https://vps.test/webhook/image-effects');
    const signed = (JSON.parse(signInit.body as string) as { payload: string }).payload;
    expect(hookInit.body).toBe(signed);
    expect((hookInit.headers as Record<string, string>)['X-Hub-Signature-256']).toBe('sha256=abc');
    expect(result.url).toContain('x.wgsl');
  });

  it('does not post to the webhook when the signer refuses', async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(jsonResponse({ detail: 'Action not allowed' }, 400));
    vi.stubGlobal('fetch', fetchMock);
    await expect(webhookSave(config, { action: 'save_shader', name: 'x', data: {} })).rejects.toThrow();
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });

  it('the client config has no secret field', async () => {
    const appConfig = await import('../../../config/appConfig');
    expect(Object.keys(appConfig).some((k) => /SECRET/i.test(k))).toBe(false);
  });
});
