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

/** Generate HMAC SHA256 signature for webhook authentication. */
export async function generateHmacSignature(payload: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const keyData = encoder.encode(secret);
  const cryptoKey = await crypto.subtle.importKey(
    'raw',
    keyData,
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const payloadData = encoder.encode(payload);
  const signatureBuffer = await crypto.subtle.sign('HMAC', cryptoKey, payloadData);
  const signatureArray = new Uint8Array(signatureBuffer);
  const signatureHex = Array.from(signatureArray)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
  return `sha256=${signatureHex}`;
}
