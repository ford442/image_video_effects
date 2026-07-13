// Shader load, hot-reload, and slot assignment.

/**
 * Load a WGSL shader
 * @param {string} id - Shader identifier
 * @param {string} wgslCode - WGSL source code
 * @returns {boolean} Success status
 */
export function loadShader(id, wgslCode) {
  if (!state.initialized || !wasmModule) {
    console.error('[WASM] Renderer not initialized');
    return false;
  }

  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);

  const codeLen = wasmModule.lengthBytesUTF8(wgslCode) + 1;
  const codePtr = wasmModule._malloc(codeLen);
  wasmModule.stringToUTF8(wgslCode, codePtr, codeLen);

  let result;
  try {
    result = wasmModule.ccall(
      'loadShader',
      'number',
      ['number', 'number'],
      [idPtr, codePtr]
    );
  } finally {
    wasmModule._free(idPtr);
    wasmModule._free(codePtr);
  }

  return result !== 0;
}

/**
 * Recompile a shader that was already loaded (hot-reload).
 * @param {string} id - Shader identifier
 * @param {string} wgslCode - WGSL source code
 * @returns {boolean} Success status
 */
export function reloadShader(id, wgslCode) {
  if (!state.initialized || !wasmModule) {
    console.error('[WASM] Renderer not initialized');
    return false;
  }

  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);

  const codeLen = wasmModule.lengthBytesUTF8(wgslCode) + 1;
  const codePtr = wasmModule._malloc(codeLen);
  wasmModule.stringToUTF8(wgslCode, codePtr, codeLen);

  let result;
  try {
    result = wasmModule.ccall(
      'reloadShader',
      'number',
      ['number', 'number'],
      [idPtr, codePtr]
    );
  } finally {
    wasmModule._free(idPtr);
    wasmModule._free(codePtr);
  }

  return result !== 0;
}

/**
 * Set the active shader for rendering (legacy single-shader API).
 * Also enables slot 0 with this shader for backwards compatibility.
 * @param {string} id - Shader identifier
 */
export function setActiveShader(id) {
  if (!state.initialized || !wasmModule) return;

  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);
  try {
    wasmModule.ccall('setActiveShader', null, ['number'], [idPtr]);
  } finally {
    wasmModule._free(idPtr);
  }

  state.activeShader = id;
}

/**
 * Assign a loaded shader to a slot (0-2).
 * @param {number} slotIndex - Slot index (0, 1, or 2)
 * @param {string} id - Shader identifier (empty string to disable the slot)
 */
export function setSlotShader(slotIndex, id) {
  if (!state.initialized || !wasmModule) return;

  const idLen = wasmModule.lengthBytesUTF8(id) + 1;
  const idPtr = wasmModule._malloc(idLen);
  wasmModule.stringToUTF8(id, idPtr, idLen);
  try {
    wasmModule.ccall('setSlotShader', null, ['number', 'number'], [slotIndex, idPtr]);
  } finally {
    wasmModule._free(idPtr);
  }
}

/**
 * Load a shader from a URL
 * @param {string} id - Shader identifier
 * @param {string} url - URL to fetch WGSL code from
 * @returns {Promise<boolean>}
 */
export async function loadShaderFromURL(id, url) {
  try {
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const wgslCode = await response.text();
    return loadShader(id, wgslCode);
  } catch (err) {
    console.error(`Failed to load shader from ${url}:`, err);
    return false;
  }
}

/**
 * Hot-reload a shader from URL (recompiles compute pipeline in C++).
 * @param {string} id - Shader identifier
 * @param {string} url - URL to fetch WGSL code from
 * @returns {Promise<boolean>}
 */
export async function reloadShaderFromURL(id, url) {
  try {
    const response = await fetch(url, { cache: 'no-store' });
    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }
    const wgslCode = await response.text();
    const ok = reloadShader(id, wgslCode);
    if (ok) {
      console.log(`[WASM] ♻️  Hot-reloaded shader: ${id}`);
    }
    return ok;
  } catch (err) {
    console.error(`Failed to reload shader from ${url}:`, err);
    return false;
  }
}
