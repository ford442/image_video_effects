// GENERATED — do not edit. Source: src/wasm/ (concat_bridge.sh / emit-wasm-bridge.mjs)

import { callAsync, callDirect, callSync, hasExport } from "./call.js";
const ASYNC_EXPORTS = ["initWasmRenderer", "loadShader", "reloadShader", "setColorFormat", "resizeCanvas"];
const EXPORT_NAMES = [
  "initWasmRenderer",
  "shutdownWasmRenderer",
  "loadShader",
  "reloadShader",
  "setActiveShader",
  "setSlotShader",
  "setSlotParams",
  "setSlotMode",
  "setColorFormat",
  "getColorFormat",
  "updateUniforms",
  "updateMousePos",
  "setMouseDown",
  "updateAudioData",
  "updateAudioFrequencyBins",
  "updateDepthMap",
  "setInputSource",
  "addRipple",
  "clearRipples",
  "setTime",
  "setZoomParams",
  "getFPS",
  "getSupportsDeepWorkgroup",
  "getSlotShaderId",
  "getSlotEnabled",
  "getSlotMode",
  "getMaxShaderSlots",
  "getCanvasCopySrcSupported",
  "setCanvasCopySrc",
  "getGPUTimings",
  "getPassTimingsJson",
  "requestWorkDoneMark",
  "getLastError",
  "getErrorRingJson",
  "clearErrorRing",
  "setRecording",
  "isRecording",
  "getAdapterSummary",
  "getLastInitErrorStage",
  "getLastInitErrorMessage",
  "isRendererInitialized",
  "loadImageData",
  "loadImageExternal",
  "uploadVideoFrame",
  "resizeCanvas",
  "beginFrameCapture",
  "getFrameCaptureState",
  "readCapturedFrame",
  "endFrameCapture",
  "getCanvasWidth",
  "getCanvasHeight"
];
function initWasmRenderer(mod, width, height, canvasSelector) {
  return callAsync(mod, "initWasmRenderer", "number", ["number", "number", "string"], [width, height, canvasSelector]).then((r) => Number(r ?? 0));
}
function shutdownWasmRenderer(mod) {
  callSync(mod, "shutdownWasmRenderer", null, [], [], "queue", void 0);
}
function loadShader(mod, id, wgslCode, workgroupX, workgroupY, usageBits) {
  return callAsync(mod, "loadShader", "number", ["number", "number", "number", "number", "number"], [id, wgslCode, workgroupX, workgroupY, usageBits]).then((r) => Number(r ?? 0));
}
function reloadShader(mod, id, wgslCode, workgroupX, workgroupY, usageBits) {
  return callAsync(mod, "reloadShader", "number", ["number", "number", "number", "number", "number"], [id, wgslCode, workgroupX, workgroupY, usageBits]).then((r) => Number(r ?? 0));
}
function setActiveShader(mod, id) {
  callSync(mod, "setActiveShader", null, ["string"], [id], "queue", void 0);
}
function setSlotShader(mod, slotIndex, id) {
  callSync(mod, "setSlotShader", null, ["number", "string"], [slotIndex, id], "queue", void 0);
}
function setSlotParams(mod, slotIndex, p1, p2, p3, p4) {
  callSync(mod, "setSlotParams", null, ["number", "number", "number", "number", "number"], [slotIndex, p1, p2, p3, p4], "call", void 0);
}
function setSlotMode(mod, slotIndex, mode) {
  callSync(mod, "setSlotMode", null, ["number", "number"], [slotIndex, mode], "call", void 0);
}
function setColorFormat(mod, formatEnum) {
  return callAsync(mod, "setColorFormat", null, ["number"], [formatEnum]).then(() => void 0);
}
function getColorFormat(mod) {
  return Number(callSync(mod, "getColorFormat", "number", [], [], "call", 0) ?? 0);
}
function updateUniforms(mod) {
  callSync(mod, "updateUniforms", null, [], [], "skip", void 0);
}
function updateMousePos(mod, x, y) {
  callSync(mod, "updateMousePos", null, ["number", "number"], [x, y], "call", void 0);
}
function setMouseDown(mod, down) {
  callSync(mod, "setMouseDown", null, ["number"], [down], "call", void 0);
}
function updateAudioData(mod, bass, mid, treble) {
  callSync(mod, "updateAudioData", null, ["number", "number", "number"], [bass, mid, treble], "call", void 0);
}
function updateAudioFrequencyBins(mod, bins, count) {
  callSync(mod, "updateAudioFrequencyBins", null, ["number", "number"], [bins, count], "call", void 0);
}
function updateDepthMap(mod, data, width, height) {
  callSync(mod, "updateDepthMap", null, ["number", "number", "number"], [data, width, height], "skip", void 0);
}
function setInputSource(mod, source) {
  callSync(mod, "setInputSource", null, ["number"], [source], "queue", void 0);
}
function addRipple(mod, x, y) {
  callSync(mod, "addRipple", null, ["number", "number"], [x, y], "call", void 0);
}
function clearRipples(mod) {
  callSync(mod, "clearRipples", null, [], [], "call", void 0);
}
function setTime(mod, time) {
  callSync(mod, "setTime", null, ["number"], [time], "call", void 0);
}
function setZoomParams(mod, p1, p2, p3, p4) {
  callSync(mod, "setZoomParams", null, ["number", "number", "number", "number"], [p1, p2, p3, p4], "call", void 0);
}
function getFPS(mod) {
  return Number(callSync(mod, "getFPS", "number", [], [], "call", 0) ?? 0);
}
function getSupportsDeepWorkgroup(mod) {
  return Number(callSync(mod, "getSupportsDeepWorkgroup", "number", [], [], "call", 0) ?? 0);
}
function getSlotShaderId(mod, slotIndex) {
  return String(callSync(mod, "getSlotShaderId", "string", ["number"], [slotIndex], "call", "") ?? "");
}
function getSlotEnabled(mod, slotIndex) {
  return Number(callSync(mod, "getSlotEnabled", "number", ["number"], [slotIndex], "call", 0) ?? 0);
}
function getSlotMode(mod, slotIndex) {
  return Number(callSync(mod, "getSlotMode", "number", ["number"], [slotIndex], "call", 0) ?? 0);
}
function getMaxShaderSlots(mod) {
  if (!hasExport(mod, "getMaxShaderSlots")) return null;
  return Number(callDirect(mod, "getMaxShaderSlots", "number", [], "call", 0) ?? 0);
}
function getCanvasCopySrcSupported(mod) {
  if (!hasExport(mod, "getCanvasCopySrcSupported")) return null;
  return Number(callDirect(mod, "getCanvasCopySrcSupported", "number", [], "call", 0) ?? 0);
}
function setCanvasCopySrc(mod, enabled) {
  if (!hasExport(mod, "setCanvasCopySrc")) return null;
  return Number(callDirect(mod, "setCanvasCopySrc", "number", [enabled], "call", 0) ?? 0);
}
function getGPUTimings(mod, parallelMs, chainedMs, totalMs, available) {
  callSync(mod, "getGPUTimings", null, ["number", "number", "number", "number"], [parallelMs, chainedMs, totalMs, available], "call", void 0);
}
function getPassTimingsJson(mod) {
  if (!hasExport(mod, "getPassTimingsJson")) return null;
  return String(callDirect(mod, "getPassTimingsJson", "string", [], "call", "") ?? "");
}
function requestWorkDoneMark(mod) {
  if (!hasExport(mod, "requestWorkDoneMark")) return null;
  return Number(callDirect(mod, "requestWorkDoneMark", "number", [], "skip", 0) ?? 0);
}
function getLastError(mod) {
  if (!hasExport(mod, "getLastError")) return null;
  return String(callDirect(mod, "getLastError", "string", [], "call", "") ?? "");
}
function getErrorRingJson(mod) {
  if (!hasExport(mod, "getErrorRingJson")) return null;
  return String(callDirect(mod, "getErrorRingJson", "string", [], "call", "") ?? "");
}
function clearErrorRing(mod) {
  if (!hasExport(mod, "clearErrorRing")) return null;
  callDirect(mod, "clearErrorRing", null, [], "call", void 0);
}
function setRecording(mod, recording) {
  callSync(mod, "setRecording", null, ["number"], [recording], "call", void 0);
}
function isRecording(mod) {
  return Number(callSync(mod, "isRecording", "number", [], [], "call", 0) ?? 0);
}
function getAdapterSummary(mod) {
  return String(callSync(mod, "getAdapterSummary", "string", [], [], "call", "") ?? "");
}
function getLastInitErrorStage(mod) {
  return Number(callSync(mod, "getLastInitErrorStage", "number", [], [], "call", 0) ?? 0);
}
function getLastInitErrorMessage(mod) {
  return String(callSync(mod, "getLastInitErrorMessage", "string", [], [], "call", "") ?? "");
}
function isRendererInitialized(mod) {
  return Number(callSync(mod, "isRendererInitialized", "number", [], [], "call", 0) ?? 0);
}
function loadImageData(mod, data, width, height) {
  callSync(mod, "loadImageData", null, ["number", "number", "number"], [data, width, height], "skip", void 0);
}
function loadImageExternal(mod, width, height) {
  return Number(callSync(mod, "loadImageExternal", "number", ["number", "number"], [width, height], "skip", 0) ?? 0);
}
function uploadVideoFrame(mod, data, width, height) {
  callSync(mod, "uploadVideoFrame", null, ["number", "number", "number"], [data, width, height], "skip", void 0);
}
function resizeCanvas(mod, newWidth, newHeight) {
  return callAsync(mod, "resizeCanvas", null, ["number", "number"], [newWidth, newHeight]).then(() => void 0);
}
function beginFrameCapture(mod) {
  callSync(mod, "beginFrameCapture", null, [], [], "skip", void 0);
}
function getFrameCaptureState(mod) {
  return Number(callSync(mod, "getFrameCaptureState", "number", [], [], "call", 0) ?? 0);
}
function readCapturedFrame(mod, outPtr, maxBytes) {
  return Number(callSync(mod, "readCapturedFrame", "number", ["number", "number"], [outPtr, maxBytes], "call", 0) ?? 0);
}
function endFrameCapture(mod) {
  callSync(mod, "endFrameCapture", null, [], [], "call", void 0);
}
function getCanvasWidth(mod) {
  return Number(callSync(mod, "getCanvasWidth", "number", [], [], "call", 0) ?? 0);
}
function getCanvasHeight(mod) {
  return Number(callSync(mod, "getCanvasHeight", "number", [], [], "call", 0) ?? 0);
}
export {
  ASYNC_EXPORTS,
  EXPORT_NAMES,
  addRipple,
  beginFrameCapture,
  clearErrorRing,
  clearRipples,
  endFrameCapture,
  getAdapterSummary,
  getCanvasCopySrcSupported,
  getCanvasHeight,
  getCanvasWidth,
  getColorFormat,
  getErrorRingJson,
  getFPS,
  getFrameCaptureState,
  getGPUTimings,
  getLastError,
  getLastInitErrorMessage,
  getLastInitErrorStage,
  getMaxShaderSlots,
  getPassTimingsJson,
  getSlotEnabled,
  getSlotMode,
  getSlotShaderId,
  getSupportsDeepWorkgroup,
  initWasmRenderer,
  isRecording,
  isRendererInitialized,
  loadImageData,
  loadImageExternal,
  loadShader,
  readCapturedFrame,
  reloadShader,
  requestWorkDoneMark,
  resizeCanvas,
  setActiveShader,
  setCanvasCopySrc,
  setColorFormat,
  setInputSource,
  setMouseDown,
  setRecording,
  setSlotMode,
  setSlotParams,
  setSlotShader,
  setTime,
  setZoomParams,
  shutdownWasmRenderer,
  updateAudioData,
  updateAudioFrequencyBins,
  updateDepthMap,
  updateMousePos,
  updateUniforms,
  uploadVideoFrame
};
