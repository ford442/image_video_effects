/**
 * stageProtocol.ts — messages between the control window and a stage window.
 *
 * The stage (`?mode=stage&output=<id>`) is a same-origin popup with no React UI.
 * It owns a <canvas>, transfers it (`transferControlToOffscreen`) to the control
 * window, which hands it to whichever thread owns the GPUDevice (the render
 * worker by default). Everything travels over `window.postMessage` with the
 * page origin as target; both sides check `event.origin` and the `px` tag.
 *
 *   stage → control   hello · canvas (transfers an OffscreenCanvas) · resize · key · bye
 *   control → stage   request-canvas · identify · close
 */

export const STAGE_TAG = 'pixelocity-stage' as const;

export type StageToControl =
  | { px: typeof STAGE_TAG; type: 'hello'; outputId: string }
  | { px: typeof STAGE_TAG; type: 'canvas'; outputId: string; canvas: OffscreenCanvas; width: number; height: number; serial: number }
  | { px: typeof STAGE_TAG; type: 'resize'; outputId: string; width: number; height: number }
  /** Calibration keys pressed in the stage window (operator standing at the projector). */
  | { px: typeof STAGE_TAG; type: 'key'; outputId: string; key: string; shift: boolean; alt: boolean }
  | { px: typeof STAGE_TAG; type: 'bye'; outputId: string };

export type ControlToStage =
  /** Make a fresh canvas and transfer it (first attach, backend switch, device-loss recovery). */
  | { px: typeof STAGE_TAG; type: 'request-canvas'; outputId: string }
  /** Flash the output's name on the stage for a moment. */
  | { px: typeof STAGE_TAG; type: 'identify'; outputId: string; label: string }
  | { px: typeof STAGE_TAG; type: 'close'; outputId: string };

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null;
const isStr = (v: unknown): v is string => typeof v === 'string' && v.length > 0 && v.length <= 64;
const isDim = (v: unknown): v is number => typeof v === 'number' && Number.isFinite(v) && v >= 1 && v <= 16384;

/** Output ids travel in URLs and storage keys: keep them boring. */
export const OUTPUT_ID_RE = /^[a-z0-9][a-z0-9-]{0,31}$/;

export function isValidOutputId(id: unknown): id is string {
  return typeof id === 'string' && OUTPUT_ID_RE.test(id);
}

export function parseStageToControl(data: unknown): StageToControl | null {
  if (!isObj(data) || data.px !== STAGE_TAG || !isValidOutputId(data.outputId)) return null;
  const outputId = data.outputId;
  switch (data.type) {
    case 'hello':
    case 'bye':
      return { px: STAGE_TAG, type: data.type, outputId };
    case 'resize':
      return isDim(data.width) && isDim(data.height)
        ? { px: STAGE_TAG, type: 'resize', outputId, width: data.width, height: data.height }
        : null;
    case 'canvas': {
      const canvas = data.canvas;
      const isCanvas = typeof OffscreenCanvas !== 'undefined' ? canvas instanceof OffscreenCanvas : isObj(canvas);
      if (!isCanvas || !isDim(data.width) || !isDim(data.height)) return null;
      const serial = typeof data.serial === 'number' && Number.isFinite(data.serial) ? data.serial : 0;
      return { px: STAGE_TAG, type: 'canvas', outputId, canvas: canvas as OffscreenCanvas, width: data.width, height: data.height, serial };
    }
    case 'key':
      return isStr(data.key)
        ? { px: STAGE_TAG, type: 'key', outputId, key: data.key, shift: data.shift === true, alt: data.alt === true }
        : null;
    default:
      return null;
  }
}

export function parseControlToStage(data: unknown, outputId: string): ControlToStage | null {
  if (!isObj(data) || data.px !== STAGE_TAG || data.outputId !== outputId) return null;
  switch (data.type) {
    case 'request-canvas':
    case 'close':
      return { px: STAGE_TAG, type: data.type, outputId };
    case 'identify':
      return { px: STAGE_TAG, type: 'identify', outputId, label: isStr(data.label) ? data.label : outputId };
    default:
      return null;
  }
}

/** URL of the stage page for an output, relative to the app root. */
export function stageUrl(outputId: string, base: string): string {
  const url = new URL(base);
  url.search = '';
  url.hash = '';
  url.searchParams.set('mode', 'stage');
  url.searchParams.set('output', outputId);
  return url.toString();
}

/** Device-pixel size of a CSS box (what the stage canvas should be). */
export function devicePixelSize(cssWidth: number, cssHeight: number, dpr: number): { width: number; height: number } {
  const r = Number.isFinite(dpr) && dpr > 0 ? dpr : 1;
  return {
    width: Math.max(1, Math.round(cssWidth * r)),
    height: Math.max(1, Math.round(cssHeight * r)),
  };
}
