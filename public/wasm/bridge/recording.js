// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import { captureFrame } from "./capture.js";
import { state, wasmRef } from "./state.js";
let _recorder = null;
let _recordChunks = [];
let _recordResolve = null;
let _recordCanvas = null;
let _recordCtx = null;
let _recordRafId = null;
let _recordFrameActive = false;
let _recordAutoStopTimer = null;
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
function startRecording(canvasElement, options = {}) {
  return new Promise((resolve, reject) => {
    if (_recorder && _recorder.state !== "inactive") {
      reject(new Error("[WASM Recording] Recording already in progress"));
      return;
    }
    const fps = options.fps ?? options.frameRate ?? 30;
    const bitrate = options.bitrate ?? options.videoBitsPerSecond ?? 5e6;
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
  if (_recorder && _recorder.state !== "inactive") {
    _recorder.stop();
  }
}
async function recordAndDownload(canvasElement, durationMs = 8e3, filename = "recording.webm") {
  const blob = await startRecording(canvasElement, { durationMs });
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
  setRecording,
  startRecording,
  stopRecording
};
