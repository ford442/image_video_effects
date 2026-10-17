import canvasConfigureContract from '../contracts/canvas_configure.json';

const STORAGE_KEY = canvasConfigureContract.optIn.displayP3.storageKey;

/** Default off — the canvas stays sRGB/standard until the user opts in. */
export function loadDisplayP3(): boolean {
  if (typeof localStorage === 'undefined') return false;
  try {
    return localStorage.getItem(STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

export function saveDisplayP3(enabled: boolean): void {
  if (typeof localStorage === 'undefined') return;
  try {
    localStorage.setItem(STORAGE_KEY, enabled ? '1' : '0');
  } catch {
    // ignore quota / privacy errors
  }
}

/** True when the page URL forces the opt-in (`?display_p3=1`), which wins over the saved setting. */
export function isDisplayP3UrlForced(
  search: string = typeof window !== 'undefined' ? window.location.search : '',
): boolean {
  const params = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search);
  return params.get(canvasConfigureContract.optIn.displayP3.urlParam) === '1';
}

export function isHdrDisplay(): boolean {
  return (
    typeof window !== 'undefined' &&
    typeof window.matchMedia === 'function' &&
    window.matchMedia(canvasConfigureContract.optIn.extendedToneMapping.requiresMediaQuery).matches
  );
}

interface AppliedColor {
  canvasColorSpace?: string;
  canvasToneMapping?: string;
  canvasColorFallback?: string;
}

const FALLBACK_TEXT: Record<string, string> = {
  'unsupported-p3': 'this browser/display rejected Display P3',
  'unsupported-extended-tone-mapping': 'extended tone mapping was rejected',
  'not-hdr-display': 'not an HDR display, extended tone mapping skipped',
};

/** One-line, user-visible explanation of the applied canvas color (from window.webgpuProbe). */
export function describeDisplayP3Status(requested: boolean, applied: AppliedColor | undefined): string {
  if (!requested) return '';
  const space = applied?.canvasColorSpace ?? 'srgb';
  const tone = applied?.canvasToneMapping ?? 'standard';
  const why = applied?.canvasColorFallback ? FALLBACK_TEXT[applied.canvasColorFallback] : undefined;
  if (space !== 'display-p3') return `Using sRGB: ${why ?? 'Display P3 not available'}`;
  return `Applied: display-p3 / ${tone}${why ? ` (${why})` : ''}`;
}
