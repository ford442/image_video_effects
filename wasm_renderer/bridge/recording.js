// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import { captureFrame } from "./capture.js";
import { readCanvasCopySrc, state, wasmRef } from "./state.js";
let _recorder = null;
let _recordChunks = [];
let _recordResolve = null;
let _recordCanvas = null;
let _recordCtx = null;
let _recordRafId = null;
let _recordFrameActive = false;
let _recordAutoStopTimer = null;
let _encodeSession = null;
let _encodeStarting = false;
let _finishEncode = null;
function cleanupRecordingPump() {
  if (_recordRafId !== null) {
    cancelAnimationFrame(_recordRafId);
    _recordRafId = null;
  }
  if (_recordAutoStopTimer !== null) {
    clearTimeout(_recordAutoStopTimer);
    _recordAutoStopTimer = null;
  }
  _recordFrameActive = false;
  _recordCanvas = null;
  _recordCtx = null;
}
function hasVideoEncoder() {
  return typeof VideoEncoder !== "undefined" && typeof VideoFrame !== "undefined";
}
function forcesMediaRecorder() {
  try {
    return new URLSearchParams(window.location.search).get("record") === "mediarecorder";
  } catch {
    return false;
  }
}
function startGpuReadbackPump(drawCanvas) {
  _recordCanvas = drawCanvas;
  _recordCtx = drawCanvas.getContext("2d");
  _recordFrameActive = false;
  const pump = () => {
    if (!_recorder || _recorder.state !== "recording") {
      cleanupRecordingPump();
      return;
    }
    if (!_recordFrameActive && state.initialized && wasmRef.module) {
      _recordFrameActive = true;
      captureFrame().then((imgData) => {
        if (_recordCtx && _recordCanvas && _recorder && _recorder.state === "recording") {
          _recordCtx.putImageData(imgData, 0, 0);
        }
      }).catch((err) => {
        console.warn("[WASM Recording] GPU readback frame skipped:", err);
      }).finally(() => {
        _recordFrameActive = false;
      });
    }
    _recordRafId = requestAnimationFrame(pump);
  };
  _recordRafId = requestAnimationFrame(pump);
}
function setRecording(active) {
  if (!state.initialized || !wasmRef.module) return;
  wasmRef.module.ccall("setRecording", null, ["number"], [active ? 1 : 0]);
}
function isRecordingActive() {
  if (!state.initialized || !wasmRef.module) return false;
  return Boolean(wasmRef.module.ccall("isRecording", "number", [], []));
}
function supportsCanvasCopySrc() {
  return typeof wasmRef.module?._setCanvasCopySrc === "function" && readCanvasCopySrc() === true;
}
function setCanvasCopySrc(enabled) {
  const mod = wasmRef.module;
  if (!state.initialized || !mod || typeof mod._setCanvasCopySrc !== "function") return false;
  if (enabled && readCanvasCopySrc() !== true) return false;
  try {
    if (!mod._setCanvasCopySrc(enabled ? 1 : 0)) return false;
  } catch (err) {
    console.warn("[WASM] canvas COPY_SRC reconfigure failed:", err);
    return false;
  }
  if (!enabled) return true;
  const ctx = wasmRef.canvas?.getContext("webgpu");
  const cfg = ctx?.getConfiguration?.();
  const copySrcBit = typeof GPUTextureUsage !== "undefined" ? GPUTextureUsage.COPY_SRC : 1;
  if (cfg && typeof cfg.usage === "number" && !(cfg.usage & copySrcBit)) {
    console.warn("[WASM] canvas COPY_SRC dropped by getConfiguration(); restoring render-only");
    mod._setCanvasCopySrc(0);
    return false;
  }
  return true;
}
function logRecordingFallback(reason, err) {
  if (err !== void 0) {
    console.warn(`[WASM Recording] fallback to MediaRecorder: ${reason}`, err);
  } else {
    console.warn(`[WASM Recording] fallback to MediaRecorder: ${reason}`);
  }
}
async function startRecording(canvasElement, options = {}) {
  if (_recorder && _recorder.state !== "inactive" || _encodeSession || _encodeStarting) {
    throw new Error("[WASM Recording] Recording already in progress");
  }
  const fps = options.fps ?? options.frameRate ?? 30;
  const bitrate = options.bitrate ?? options.videoBitsPerSecond ?? 5e6;
  if (forcesMediaRecorder()) {
    logRecordingFallback("?record=mediarecorder");
  } else if (!hasVideoEncoder()) {
    logRecordingFallback("VideoEncoder / VideoFrame unavailable");
  } else if (!options.gpuEncode) {
    logRecordingFallback("no WebCodecs starter injected");
  } else if (state.initialized && wasmRef.module) {
    _encodeStarting = true;
    let session = null;
    try {
      session = await options.gpuEncode(captureFrame, {
        width: state.canvasWidth || canvasElement.width,
        height: state.canvasHeight || canvasElement.height,
        fps,
        bitrate
      });
      if (!session) logRecordingFallback("no supported WebM codec for VideoEncoder");
    } catch (err) {
      logRecordingFallback("WebCodecs session failed to start", err);
    } finally {
      _encodeStarting = false;
    }
    if (session) return runEncodeSession(session, options.durationMs);
  }
  return startMediaRecorder(canvasElement, options, fps, bitrate);
}
function runEncodeSession(session, durationMs) {
  _encodeSession = session;
  setRecording(true);
  console.log(`[WASM Recording] WebCodecs take started (source=${session.kind ?? "unknown"})`);
  return new Promise((resolve, reject) => {
    _finishEncode = () => {
      _finishEncode = null;
      _encodeSession = null;
      session.stop().then(resolve, reject).finally(() => setRecording(false));
    };
    if (durationMs && durationMs > 0) {
      _recordAutoStopTimer = setTimeout(stopRecording, durationMs);
    }
  });
}
function startMediaRecorder(canvasElement, options, fps, bitrate) {
  return new Promise((resolve, reject) => {
    const mimeType = options.mimeType || (MediaRecorder.isTypeSupported("video/webm;codecs=vp9") ? "video/webm;codecs=vp9" : MediaRecorder.isTypeSupported("video/webm") ? "video/webm" : "video/mp4");
    _recordChunks = [];
    _recordResolve = resolve;
    setRecording(true);
    try {
      let stream;
      if (state.initialized && wasmRef.module) {
        const offscreen = document.createElement("canvas");
        offscreen.width = canvasElement.width || 2048;
        offscreen.height = canvasElement.height || 2048;
        stream = offscreen.captureStream(fps);
        startGpuReadbackPump(offscreen);
      } else {
        stream = canvasElement.captureStream(fps);
      }
      _recorder = new MediaRecorder(stream, {
        mimeType,
        videoBitsPerSecond: bitrate
      });
    } catch (err) {
      setRecording(false);
      cleanupRecordingPump();
      const message = err instanceof Error ? err.message : String(err);
      reject(new Error(`[WASM Recording] MediaRecorder failed: ${message}`));
      return;
    }
    _recorder.ondataavailable = (e) => {
      if (e.data && e.data.size > 0) {
        _recordChunks.push(e.data);
      }
    };
    _recorder.onstop = () => {
      const blob = new Blob(_recordChunks, { type: mimeType });
      setRecording(false);
      cleanupRecordingPump();
      if (_recordResolve) {
        _recordResolve(blob);
        _recordResolve = null;
      }
      _recorder = null;
      _recordChunks = [];
    };
    _recorder.onerror = (e) => {
      setRecording(false);
      cleanupRecordingPump();
      const error = e.error;
      reject(new Error(`[WASM Recording] MediaRecorder error: ${error}`));
      _recorder = null;
    };
    _recorder.start(100);
    if (options.durationMs && options.durationMs > 0) {
      _recordAutoStopTimer = setTimeout(() => {
        stopRecording();
      }, options.durationMs);
    }
  });
}
function stopRecording() {
  if (_recordAutoStopTimer !== null) {
    clearTimeout(_recordAutoStopTimer);
    _recordAutoStopTimer = null;
  }
  if (_finishEncode) {
    _finishEncode();
    return;
  }
  if (_recorder && _recorder.state !== "inactive") {
    _recorder.stop();
  }
}
async function recordAndDownload(canvasElement, durationMs = 8e3, filename = "recording.webm", gpuEncode) {
  const blob = await startRecording(canvasElement, { durationMs, gpuEncode });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}
export {
  isRecordingActive,
  recordAndDownload,
  setCanvasCopySrc,
  setRecording,
  startRecording,
  stopRecording,
  supportsCanvasCopySrc
};
