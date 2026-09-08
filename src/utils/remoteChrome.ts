/** Local remote-window chrome flag. Not part of FullState / BroadcastChannel. */

export function isRemoteChromeHidden(search: string = window.location.search): boolean {
    const raw = search.startsWith('?') ? search.slice(1) : search;
    return new URLSearchParams(raw).get('chrome') === 'hide';
}

export function writeRemoteChromeParam(hidden: boolean): void {
    const params = new URLSearchParams(window.location.search);
    if (hidden) {
        params.set('chrome', 'hide');
    } else {
        params.delete('chrome');
    }
    const qs = params.toString();
    window.history.replaceState(
        null,
        '',
        `${window.location.pathname}${qs ? `?${qs}` : ''}${window.location.hash}`,
    );
}
