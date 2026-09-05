// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import {
  captureFrame,
  captureFrameDataUrl,
  resizeCanvas,
  takeScreenshot,
  uploadImageData,
  uploadVideoFrame
} from "./capture.js";
import { getDiagnostics } from "./diagnostics.js";
import { initWasmRenderer, isInitialized, shutdownWasmRenderer } from "./init.js";
import {
  isRecordingActive,
  recordAndDownload,
  setRecording,
  startRecording,
  stopRecording
} from "./recording.js";
import {
  getSlotState,
  loadShader,
  loadShaderFromURL,
  reloadShader,
  reloadShaderFromURL,
  setActiveShader,
  setSlotMode,
  setSlotShader
} from "./shader.js";
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
  getGPUTimings,
  setRecording,
  isRecordingActive,
  captureFrameDataUrl,
  getAdapterSummary,
  getLastInitErrorStage,
  getLastInitErrorMessage,
  isInitialized,
  uploadImageData,
  uploadVideoFrame,
  resizeCanvas,
  setColorFormat,
  captureFrame,
  takeScreenshot,
  startRecording,
  stopRecording,
  recordAndDownload
};
var api_default = wasmBridge;
export {
  api_default as default
};
