import { afterEach, describe, expect, it, vi } from 'vitest';
import { reportError } from './ErrorHandling';
import {
  dismissErrorNotice,
  getErrorNotice,
  installErrorNoticeHandler,
  subscribeErrorNotice,
  toErrorNotice,
} from './errorNotices';

describe('toErrorNotice', () => {
  it('names the shader for compile failures and keys by shader id', () => {
    const a = toErrorNotice({ type: 'shader-compile', message: 'Shader "foo" failed to compile. Trying fallback pass-through shader.', recoverable: true });
    const b = toErrorNotice({ type: 'shader-compile', message: 'Shader "foo" failed to compile. Slot skipped — pipeline not submitted.', recoverable: true });
    expect(a?.kind).toBe('shader');
    expect(a?.message).toContain('“foo”');
    expect(a?.key).toBe(b?.key); // the two reports of one failure collapse
  });

  it('reports unreachable images with recovery wording', () => {
    const n = toErrorNotice({ type: 'media-load', message: 'Failed to load image "https://x/y.jpg": Failed to fetch', recoverable: true });
    expect(n?.kind).toBe('image');
    expect(n?.message).toMatch(/unreachable/i);
    expect(n?.message).not.toContain('https://x/y.jpg'); // no raw URLs / jargon
  });

  it('reports video playback errors', () => {
    expect(toErrorNotice({ type: 'media-load', message: 'Video error: Network error while loading video', recoverable: true })?.kind).toBe('video');
  });

  it('stays quiet for internal fallbacks and errors that have their own overlays', () => {
    expect(toErrorNotice({ type: 'media-load', message: 'Video ingest fell back to the element path (x)', recoverable: true })).toBeNull();
    expect(toErrorNotice({ type: 'media-load', message: 'Video frame import failed: x', recoverable: true })).toBeNull();
    for (const type of ['webgpu-unavailable', 'device-lost', 'gpu-validation', 'render-frame', 'wasm-init'] as const) {
      expect(toErrorNotice({ type, message: 'x', recoverable: true })).toBeNull();
    }
  });
});

describe('installErrorNoticeHandler', () => {
  let uninstall: (() => void) | undefined;
  afterEach(() => {
    uninstall?.();
    uninstall = undefined;
    vi.restoreAllMocks();
  });

  it('publishes a notice, still logs to the console, and notifies subscribers once per cause', () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => undefined);
    const listener = vi.fn();
    const unsub = subscribeErrorNotice(listener);
    uninstall = installErrorNoticeHandler();

    reportError({ type: 'shader-compile', message: 'Shader "bar" failed to compile. Trying fallback pass-through shader.', recoverable: true });
    reportError({ type: 'shader-compile', message: 'Shader "bar" failed to compile. Slot skipped — pipeline not submitted.', recoverable: true });
    expect(getErrorNotice()?.kind).toBe('shader');
    expect(listener).toHaveBeenCalledTimes(1);
    expect(log).toHaveBeenCalledTimes(2);

    dismissErrorNotice();
    expect(getErrorNotice()).toBeNull();
    unsub();
  });

  it('uninstall restores the console handler and clears the notice', () => {
    vi.spyOn(console, 'error').mockImplementation(() => undefined);
    uninstall = installErrorNoticeHandler();
    reportError({ type: 'media-load', message: 'Failed to load image "u": boom', recoverable: true });
    expect(getErrorNotice()).not.toBeNull();
    uninstall();
    uninstall = undefined;
    expect(getErrorNotice()).toBeNull();
    reportError({ type: 'media-load', message: 'Failed to load image "u": boom', recoverable: true });
    expect(getErrorNotice()).toBeNull();
  });
});
