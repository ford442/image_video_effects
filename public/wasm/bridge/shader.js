// src/wasm/bridge/shader.js
// Shader load, hot-reload, and slot assignment.

import { state, wasmRef } from './state.js';
import { rewriteWgslStorageFormats } from './wgslFormat.js';

/**
 * Load a WGSL shader
 * @param {string} id - Shader identifier
 * @param {string} wgslCode - WGSL source code
 * @returns {boolean} Success status
 */
export function loadShader(id, wgslCode) {
  if (!state.initialized || !wasmRef.module) {
    console.error('[WASM] Renderer not initialized');
    return false;
  }

  const rewritten = rewriteWgslStorageFormats(wgslCode, state.colorFormat);

  const idLen = wasmRef.module.lengthBytesUTF8(id) + 1;
  const idPtr = wasmRef.module._malloc(idLen);
  wasmRef.module.stringToUTF8(id, idPtr, idLen);

  const codeLen = wasmRef.module.lengthBytesUTF8(rewritten) + 1;
  const codePtr = wasmRef.module._malloc(codeLen);
  wasmRef.module.stringToUTF8(rewritten, codePtr, codeLen);

  const result = wasmRef.module.ccall(
    'loadShader',
    'number',
    ['number', 'number'],
    [idPtr, codePtr]
  );

  wasmRef.module._free(idPtr);
  wasmRef.module._free(codePtr);

  if (result) {
    state.activeShader = id;
    console.log(`[WASM] Loaded shader: ${id}`);
    return true;
  } else {
    console.error(`[WASM] Failed to load shader: ${id}`);
    state.lastLoadError = `Failed to compile/load shader: ${id}`;
    state.loadErrorCount++;
    return false;
  }
}

/**
 * Hot-reload a WGSL shader without recreating pipelines if possible
 * @param {string} id - Shader identifier
 * @param {string} wgslCode - New WGSL source code
 * @returns {boolean} Success status
 */
export function reloadShader(id, wgslCode) {
  if (!state.initialized || !wasmRef.module) {
    console.error('[WASM] Renderer not initialized');
    return false;
  }

  const rewritten = rewriteWgslStorageFormats(wgslCode, state.colorFormat);

  const idLen = wasmRef.module.lengthBytesUTF8(id) + 1;
  const idPtr = wasmRef.module._malloc(idLen);
  wasmRef.module.stringToUTF8(id, idPtr, idLen);

  const codeLen = wasmRef.module.lengthBytesUTF8(rewritten) + 1;
  const codePtr = wasmRef.module._malloc(codeLen);
  wasmRef.module.stringToUTF8(rewritten, codePtr, codeLen);

  const result = wasmRef.module.ccall(
    'reloadShader',
    'number',
    ['number', 'number'],
    [idPtr, codePtr]
  );

  wasmRef.module._free(idPtr);
  wasmRef.module._free(codePtr);

  if (result) {
    console.log(`[WASM] Hot-reloaded shader: ${id}`);
    return true;
  } else {
    console.error(`[WASM] Hot-reload failed for: ${id}`);
    state.lastLoadError = `Hot-reload failed: ${id}`;
    state.loadErrorCount++;
    return false;
  }
}

/**
 * Load a shader from a URL
 * @param {string} id - Shader identifier
 * @param {string} url - URL to fetch WGSL from
 * @returns {Promise<boolean>} Success status
 */
export async function loadShaderFromURL(id, url) {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP error ${response.status}: ${response.statusText}`);
    }
    const wgslCode = await response.text();
    return loadShader(id, wgslCode);
  } catch (err) {
    console.error(`[WASM] Failed to fetch shader from ${url}:`, err);
    state.lastLoadError = `Fetch failed (${url}): ${err.message}`;
    state.loadErrorCount++;
    return false;
  }
}

/**
 * Hot-reload a shader from a URL
 * @param {string} id - Shader identifier
 * @param {string} url - URL to fetch WGSL from
 * @returns {Promise<boolean>} Success status
 */
export async function reloadShaderFromURL(id, url) {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP error ${response.status}: ${response.statusText}`);
    }
    const wgslCode = await response.text();
    return reloadShader(id, wgslCode);
  } catch (err) {
    console.error(`[WASM] Failed to fetch shader for reload from ${url}:`, err);
    state.lastLoadError = `Reload fetch failed (${url}): ${err.message}`;
    state.loadErrorCount++;
    return false;
  }
}

/**
 * Set the active shader for single-shader rendering
 * @param {string} id - Shader identifier
 * @returns {boolean} Success status
 */
export function setActiveShader(id) {
  if (!state.initialized || !wasmRef.module) {
    return false;
  }

  const result = wasmRef.module.ccall(
    'setActiveShader',
    'number',
    ['string'],
    [id]
  );

  if (result) {
    state.activeShader = id;
    return true;
  }
  return false;
}

/**
 * Assign a compiled shader to a pipeline slot (0, 1, or 2).
 * @param {number} slotIndex - Slot index (0=Background, 1=Layer1, 2=Layer2)
 * @param {string} shaderId - Shader identifier (empty string to disable slot)
 * @returns {boolean} Success status
 */
export function setSlotShader(slotIndex, shaderId) {
  if (!state.initialized || !wasmRef.module) return false;
  return Boolean(
    wasmRef.module.ccall(
      'setSlotShader',
      'number',
      ['number', 'string'],
      [slotIndex, shaderId]
    )
  );
}

/**
 * Set the blend mode for a pipeline slot.
 * @param {number} slotIndex - Slot index (0, 1, or 2)
 * @param {number} mode - 0=Normal, 1=Additive, 2=Multiply, 3=Screen, 4=Overlay
 */
export function setSlotMode(slotIndex, mode) {
  if (!state.initialized || !wasmRef.module) return;
  wasmRef.module.ccall(
    'setSlotMode',
    null,
    ['number', 'number'],
    [slotIndex, mode]
  );
}

/**
 * Get the shader ID bound to a slot (C++ string readback).
 * @param {number} slotIndex
 * @returns {string} Shader ID or empty string if unbound/invalid slot
 */
export function getSlotShaderId(slotIndex) {
  if (!state.initialized || !wasmRef.module) return '';
  return (
    wasmRef.module.ccall(
      'getSlotShaderId',
      'string',
      ['number'],
      [slotIndex]
    ) ?? ''
  );
}

/**
 * Check if a slot is enabled and has a valid shader bound.
 * @param {number} slotIndex
 * @returns {boolean}
 */
export function getSlotEnabled(slotIndex) {
  if (!state.initialized || !wasmRef.module) return false;
  return Boolean(
    wasmRef.module.ccall(
      'getSlotEnabled',
      'number',
      ['number'],
      [slotIndex]
    )
  );
}

/**
 * Get the blend mode of a slot (0..4).
 * @param {number} slotIndex
 * @returns {number}
 */
export function getSlotMode(slotIndex) {
  if (!state.initialized || !wasmRef.module) return 0;
  return (
    wasmRef.module.ccall(
      'getSlotMode',
      'number',
      ['number'],
      [slotIndex]
    ) ?? 0
  );
}

/**
 * Full inspection helper for a pipeline slot.
 * @param {number} slotIndex
 * @returns {{ shaderId: string, enabled: boolean, mode: number }}
 */
export function getSlotState(slotIndex) {
  return {
    shaderId: getSlotShaderId(slotIndex),
    enabled: getSlotEnabled(slotIndex),
    mode: getSlotMode(slotIndex),
  };
}
