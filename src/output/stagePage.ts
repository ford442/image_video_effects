/**
 * stagePage.ts — the stage window (`?mode=stage&output=<id>`): one canvas, no UI.
 *
 * Mounted by index.tsx instead of React. It never renders anything itself: it
 * transfers its canvas to the control window, which hands it to the renderer.
 * F (or a double-click) toggles fullscreen on whatever display the window is on;
 * that is the first-class path, and the only one where the Window Management
 * API is unavailable. Arrow keys / Tab are forwarded for corner calibration.
 */

import { devicePixelSize, parseControlToStage, STAGE_TAG, type StageToControl } from './stageProtocol';

const FORWARDED_KEYS = new Set(['ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'Tab', '1', '2', '3', '4', 't', 'o']);

export interface StagePageHandle {
  dispose(): void;
}

export function mountStage(win: Window, outputId: string): StagePageHandle {
  const doc = win.document;
  const origin = win.location.origin;
  doc.title = `Pixelocity stage · ${outputId}`;
  const style = doc.createElement('style');
  style.textContent = `
    html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
    canvas { position: fixed; inset: 0; width: 100vw; height: 100vh; display: block; }
    body.fs { cursor: none; }
    .px-stage-hint { position: fixed; left: 16px; bottom: 16px; font: 14px/1.4 system-ui, sans-serif;
      color: #ddd; background: rgba(0,0,0,0.65); padding: 8px 12px; border-radius: 6px;
      transition: opacity 0.6s; pointer-events: none; }
    .px-stage-hint.hidden { opacity: 0; }
    .px-stage-id { position: fixed; inset: 0; display: flex; align-items: center; justify-content: center;
      font: 700 12vh/1 system-ui, sans-serif; color: #fff; text-shadow: 0 0 24px #000;
      pointer-events: none; transition: opacity 0.4s; }
  `;
  doc.head.appendChild(style);
  const root = doc.getElementById('root') ?? doc.body;

  const hint = doc.createElement('div');
  hint.className = 'px-stage-hint';
  hint.textContent = `Stage “${outputId}” — move this window to the projector and press F for fullscreen.`;
  doc.body.appendChild(hint);
  let hintTimer: ReturnType<typeof setTimeout> | null = null;
  const showHint = (ms = 6000) => {
    hint.classList.remove('hidden');
    if (hintTimer) clearTimeout(hintTimer);
    hintTimer = setTimeout(() => hint.classList.add('hidden'), ms);
  };
  showHint();

  const post = (msg: StageToControl, transfer: Transferable[] = []) => {
    const opener = win.opener as Window | null;
    if (!opener || opener.closed) {
      hint.textContent = 'The control window is gone — close this stage and open a new one.';
      showHint(60_000);
      return;
    }
    opener.postMessage(msg, { targetOrigin: origin, transfer });
  };

  let canvas: HTMLCanvasElement | null = null;
  let serial = 0;
  const size = () => devicePixelSize(win.innerWidth, win.innerHeight, win.devicePixelRatio);

  /** A canvas is bound to the thread it was transferred to; every attach needs a fresh one. */
  const sendCanvas = () => {
    canvas?.remove();
    const c = doc.createElement('canvas');
    const { width, height } = size();
    c.width = width;
    c.height = height;
    root.appendChild(c);
    canvas = c;
    if (typeof c.transferControlToOffscreen !== 'function') {
      hint.textContent = 'This browser cannot hand a canvas to the renderer (no OffscreenCanvas).';
      showHint(60_000);
      return;
    }
    const offscreen = c.transferControlToOffscreen();
    serial += 1;
    post({ px: STAGE_TAG, type: 'canvas', outputId, canvas: offscreen, width, height, serial }, [offscreen]);
  };

  let lastSize = '';
  const onResize = () => {
    const { width, height } = size();
    const key = `${width}x${height}`;
    if (key === lastSize) return;
    lastSize = key;
    post({ px: STAGE_TAG, type: 'resize', outputId, width, height });
  };

  const toggleFullscreen = () => {
    if (doc.fullscreenElement) void doc.exitFullscreen?.().catch(() => undefined);
    else void doc.documentElement.requestFullscreen?.({ navigationUI: 'hide' }).catch(() => undefined);
  };
  const onFullscreen = () => {
    doc.body.classList.toggle('fs', !!doc.fullscreenElement);
    if (!doc.fullscreenElement) showHint();
    else hint.classList.add('hidden');
  };

  const onKey = (e: KeyboardEvent) => {
    if (e.key === 'f' || e.key === 'F') {
      e.preventDefault();
      toggleFullscreen();
      return;
    }
    if (FORWARDED_KEYS.has(e.key)) {
      e.preventDefault();
      post({ px: STAGE_TAG, type: 'key', outputId, key: e.key, shift: e.shiftKey, alt: e.altKey });
    }
  };

  let idEl: HTMLDivElement | null = null;
  const identify = (label: string) => {
    idEl?.remove();
    const el = doc.createElement('div');
    el.className = 'px-stage-id';
    el.textContent = label;
    doc.body.appendChild(el);
    idEl = el;
    setTimeout(() => { el.style.opacity = '0'; }, 1500);
    setTimeout(() => el.remove(), 2200);
  };

  const onMessage = (e: MessageEvent) => {
    if (e.origin !== origin || e.source !== win.opener) return;
    const msg = parseControlToStage(e.data, outputId);
    if (!msg) return;
    if (msg.type === 'request-canvas') sendCanvas();
    else if (msg.type === 'identify') identify(msg.label);
    else if (msg.type === 'close') win.close();
  };

  const onHide = () => post({ px: STAGE_TAG, type: 'bye', outputId });

  win.addEventListener('message', onMessage);
  win.addEventListener('resize', onResize);
  win.addEventListener('keydown', onKey);
  win.addEventListener('dblclick', toggleFullscreen);
  win.addEventListener('pagehide', onHide);
  doc.addEventListener('fullscreenchange', onFullscreen);

  post({ px: STAGE_TAG, type: 'hello', outputId });

  return {
    dispose() {
      win.removeEventListener('message', onMessage);
      win.removeEventListener('resize', onResize);
      win.removeEventListener('keydown', onKey);
      win.removeEventListener('dblclick', toggleFullscreen);
      win.removeEventListener('pagehide', onHide);
      doc.removeEventListener('fullscreenchange', onFullscreen);
      if (hintTimer) clearTimeout(hintTimer);
    },
  };
}
