/**
 * ErrorHandling.ts
 *
 * Centralized error handling for WebGPU renderer with browser detection.
 */

export interface RendererError {
  type: 'webgpu-unavailable' | 'shader-compile' | 'media-load' | 'device-lost' | 'wasm-unavailable' | 'wasm-init' | 'wasm-device-lost' | 'gpu-validation' | 'render-frame';
  message: string;
  recoverable: boolean;
}

export type ErrorHandler = (error: RendererError) => void;

/** Default handler: logs to the console. Handlers that surface UI should still call this. */
export const consoleErrorHandler: ErrorHandler = (error) => {
  console.error(`[WebGPU Renderer] ${error.type}: ${error.message}`);
};

let globalErrorHandler: ErrorHandler = consoleErrorHandler;

export function setRendererErrorHandler(handler: ErrorHandler) {
  globalErrorHandler = handler;
}

export function reportError(error: RendererError) {
  globalErrorHandler(error);
}

/**
 * Browser detection for WebGPU warnings
 * @returns Warning message if WebGPU is unavailable, null otherwise
 */
export function getBrowserWarning(): string | null {
  const ua = navigator.userAgent.toLowerCase();

  // Safari / iOS: WebGPU shipped in Safari 26 and iOS 26, so this only fires on older versions.
  if (ua.includes('safari') && !ua.includes('chrome') && !ua.includes('chromium')) {
    return /iphone|ipad|ipod/.test(ua)
      ? 'This iOS version does not support WebGPU. Update to iOS 26 or later, or use a desktop browser such as Chrome or Edge.'
      : 'This version of Safari does not support WebGPU. Update to Safari 26 or later, or use Chrome or Edge.';
  }

  // iOS (non-Safari browsers use the same engine)
  if (/iphone|ipad|ipod/.test(ua)) {
    return 'This iOS version does not support WebGPU. Update to iOS 26 or later, or use a desktop browser such as Chrome or Edge.';
  }

  // Firefox only exposes WebGPU on some platforms and versions.
  if (ua.includes('firefox')) {
    return 'This version of Firefox does not have WebGPU available. Try the latest Chrome or Edge.';
  }

  // Older browser check
  if (!navigator.gpu) {
    return 'Your browser does not support WebGPU. Please update to the latest Chrome or Edge.';
  }

  return null;
}

/**
 * Validates WebGPU is available and ready to use
 * @returns true if WebGPU is available, false otherwise
 */
export function isWebGPUAvailable(): boolean {
  return !!navigator.gpu;
}
