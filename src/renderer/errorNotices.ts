/**
 * User-facing notices for renderer errors (Release 3/5 error-state audit).
 *
 * The renderer reports shader-compile / media-load failures through reportError(), which on the
 * main thread only logged to the console — the UI kept saying "Ready." while the slot was skipped
 * or the media host was unreachable. This turns the recoverable ones into a single friendly notice
 * with a recovery action. WebGPU-unavailable and device-lost already have their own overlays;
 * per-frame validation noise and internal fallbacks that still render are deliberately not shown.
 */
import { consoleErrorHandler, setRendererErrorHandler, type RendererError } from './ErrorHandling';

export type ErrorNoticeKind = 'shader' | 'image' | 'video';

export interface ErrorNotice {
  /** Stable per cause, so repeated reports of the same failure collapse into one notice. */
  key: string;
  kind: ErrorNoticeKind;
  message: string;
}

/** Map a renderer error to a notice, or null when it is not worth interrupting the user. */
export function toErrorNotice(error: RendererError): ErrorNotice | null {
  if (error.type === 'shader-compile') {
    const id = /Shader "([^"]+)"/.exec(error.message)?.[1];
    const subject = id ? `The effect “${id}”` : 'That effect';
    return {
      key: `shader:${id ?? 'unknown'}`,
      kind: 'shader',
      message: `${subject} couldn’t run on this GPU, so it was skipped. Try another effect.`,
    };
  }
  if (error.type === 'media-load') {
    if (/fell back|frame import failed/i.test(error.message)) return null; // internal, still renders
    if (/^Failed to load image/i.test(error.message)) {
      return {
        key: 'media:image',
        kind: 'image',
        message: 'Couldn’t load that image — the media server may be unreachable. Check your connection, try another image, or switch to the generative source.',
      };
    }
    if (/video/i.test(error.message)) {
      return {
        key: 'media:video',
        kind: 'video',
        message: 'That video couldn’t be played (the file may be unreachable or unsupported). Try another source.',
      };
    }
  }
  return null;
}

let current: ErrorNotice | null = null;
const listeners = new Set<() => void>();

function emit(): void {
  for (const l of listeners) l();
}

export function getErrorNotice(): ErrorNotice | null {
  return current;
}

export function subscribeErrorNotice(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}

export function dismissErrorNotice(): void {
  if (current === null) return;
  current = null;
  emit();
}

/** Route renderer errors to the notice store (still logging to the console). Returns an uninstall. */
export function installErrorNoticeHandler(): () => void {
  setRendererErrorHandler((error) => {
    consoleErrorHandler(error);
    const notice = toErrorNotice(error);
    if (notice && current?.key !== notice.key) {
      current = notice;
      emit();
    }
  });
  return () => {
    setRendererErrorHandler(consoleErrorHandler);
    dismissErrorNotice();
  };
}
