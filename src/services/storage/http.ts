/**
 * HTTP helpers: path encoding, error mapping, JSON fetch.
 */

export class StorageHttpError extends Error {
  readonly status: number;
  readonly statusText: string;
  readonly body?: string;

  constructor(status: number, statusText: string, body?: string) {
    const detail = body?.trim() ? `: ${body.trim()}` : '';
    super(`HTTP ${status} ${statusText}${detail}`);
    this.name = 'StorageHttpError';
    this.status = status;
    this.statusText = statusText;
    this.body = body;
  }
}

/** Encode a single path segment for use in REST URLs (shader id, filename stem, etc.). */
export function encodeResourcePath(segment: string): string {
  return encodeURIComponent(segment.trim());
}

/** Build a static or absolute URL from a relative storage path. */
export function resolveStaticUrl(staticBase: string, path: string): string {
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  const base = staticBase.replace(/\/$/, '');
  const relative = path.replace(/^\//, '');
  return `${base}/${relative}`;
}

/** Map a failed fetch Response to StorageHttpError. */
export async function mapHttpError(response: Response): Promise<StorageHttpError> {
  let body: string | undefined;
  try {
    body = await response.text();
  } catch {
    body = undefined;
  }
  return new StorageHttpError(response.status, response.statusText, body);
}

/** Throw StorageHttpError when response is not ok. */
export async function assertOk(response: Response): Promise<Response> {
  if (!response.ok) {
    throw await mapHttpError(response);
  }
  return response;
}

export async function fetchJson<T>(url: string, init?: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  await assertOk(response);
  return response.json() as Promise<T>;
}

export async function fetchText(url: string, init?: RequestInit): Promise<string> {
  const response = await fetch(url, init);
  await assertOk(response);
  return response.text();
}

/** Normalize list endpoints that return either a bare array or `{ key: T[] }`. */
export function unwrapListResponse<T>(
  data: T[] | Record<string, unknown>,
  key: string
): T[] {
  if (Array.isArray(data)) {
    return data;
  }
  if (data && typeof data === 'object') {
    const wrapped = (data as Record<string, unknown>)[key];
    if (Array.isArray(wrapped)) {
      return wrapped as T[];
    }
  }
  throw new Error(`Invalid response format: expected array or { ${key}: [] }`);
}

/**
 * Ask storage_manager to sign a webhook payload. The HMAC secret lives only on the server;
 * the server checks the action and timestamp before signing.
 */
export async function requestWebhookSignature(signUrl: string, payload: string): Promise<string> {
  const response = await fetch(signUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ payload }),
  });
  await assertOk(response);
  const body = (await response.json()) as { signature?: unknown };
  if (typeof body.signature !== 'string' || !body.signature.startsWith('sha256=')) {
    throw new Error('Storage signer returned no signature');
  }
  return body.signature;
}
