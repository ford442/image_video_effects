// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import {
  captureFrame,
  captureFrameDataUrl,
  resizeCanvas,
  takeScreenshot,
  uploadImageData,
  uploadImageSource,
  uploadVideoFrame
} from "./capture.js";
import { getDiagnostics } from "./diagnostics.js";
import {
  getPresentCanvas,
  getPresentCanvasId,
  initWasmRenderer,
  isInitialized,
  shutdownWasmRenderer
} from "./init.js";
import {
  isRecordingActive,
  recordAndDownload,
  setCanvasCopySrc,
  setRecording,
  startRecording,
  stopRecording,
  supportsCanvasCopySrc
} from "./recording.js";
import {
  getDroppedSlots,
  getSlotState,
  loadShader,
  loadShaderFromURL,
  reloadShader,
  reloadShaderFromURL,
  setActiveShader,
  setSlotMode,
  setSlotShader
} from "./shader.js";
import { isCppRendererReady, readCanvasCopySrc } from "./state.js";
import {
  addRipple,
  clearRipples,
  getAdapterSummary,
  getColorFormat,
  getFPS,
  getGPUTimings,
  getLastInitErrorMessage,
  getLastInitErrorStage,
  getSupportsDeepWorkgroup,
  setColorFormat,
  setInputSource,
  setSlotParams,
  updateAudioData,
  updateAudioFrequencyBins,
  updateDepthMap,
  updateMousePos,
  updateSlotParams,
  updateUniforms
} from "./uniforms.js";
const wasmBridge = {
  getDiagnostics,
  initWasmRenderer,
  getPresentCanvas,
  getPresentCanvasId,
  shutdownWasmRenderer,
  loadShader,
  reloadShader,
  loadShaderFromURL,
  reloadShaderFromURL,
  setActiveShader,
  setSlotShader,
  setSlotParams,
  updateSlotParams,
  setSlotMode,
  updateUniforms,
  updateMousePos,
  updateAudioData,
  updateAudioFrequencyBins,
  updateDepthMap,
  setInputSource,
  addRipple,
  clearRipples,
  getFPS,
  getSupportsDeepWorkgroup,
  getColorFormat,
  getSlotState,
  getDroppedSlots,
  getGPUTimings,
  setRecording,
  isRecordingActive,
  captureFrameDataUrl,
  getAdapterSummary,
  getLastInitErrorStage,
  getLastInitErrorMessage,
  isInitialized,
  uploadImageData,
  uploadImageSource,
  uploadVideoFrame,
  resizeCanvas,
  setColorFormat,
  captureFrame,
  takeScreenshot,
  startRecording,
  stopRecording,
  recordAndDownload,
  supportsCanvasCopySrc,
  setCanvasCopySrc,
  isCppRendererReady,
  readCanvasCopySrc
};
var api_default = wasmBridge;
export {
  api_default as default
};
