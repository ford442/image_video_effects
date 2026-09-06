const STORAGE_KEY = 'px_source_auto_exposure';

/** Default off — catalog path stays raw until the user opts in. */
export function loadSourceAutoExposure(): boolean {
  if (typeof localStorage === 'undefined') return false;
  try {
    return localStorage.getItem(STORAGE_KEY) === '1';
  } catch {
    return false;
  }
}

export function saveSourceAutoExposure(enabled: boolean): void {
  if (typeof localStorage === 'undefined') return;
  try {
    localStorage.setItem(STORAGE_KEY, enabled ? '1' : '0');
  } catch {
    // ignore quota / privacy errors
  }
}
