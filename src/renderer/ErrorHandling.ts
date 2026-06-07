/**
 * ErrorHandling.ts
 *
 * Centralized error handling for WebGPU renderer with browser detection.
 */

export interface RendererError {
  type: 'webgpu-unavailable' | 'shader-compile' | 'media-load' | 'device-lost' | 'wasm-unavailable' | 'wasm-init' | 'wasm-device-lost';
  message: string;
  recoverable: boolean;
}

export type ErrorHandler = (error: RendererError) => void;

// Default error handler that logs to console
let globalErrorHandler: ErrorHandler = (error) => {
  console.error(`[WebGPU Renderer] ${error.type}: ${error.message}`);
};

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

  // Safari check (all versions as of 2026)
  if (ua.includes('safari') && !ua.includes('chrome') && !ua.includes('chromium')) {
    return 'Safari does not support WebGPU. Please use Chrome, Edge, or Firefox Nightly.';
  }

  // iOS check
  if (/iphone|ipad|ipod/.test(ua)) {
    return 'WebGPU is not available on iOS. Please use a desktop browser.';
  }

  // Older browser check
  if (!navigator.gpu) {
    return 'Your browser does not support WebGPU. Please update to the latest Chrome, Edge, or Firefox.';
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
