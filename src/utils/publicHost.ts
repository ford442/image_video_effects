/** Public production host — remote control is test/dev only. */
export const PUBLIC_PIXELLOCITY_HOSTS = new Set(['go.1ink.us', 'www.go.1ink.us']);

export function isPublicPixelocityHost(hostname: string = window.location.hostname): boolean {
    return PUBLIC_PIXELLOCITY_HOSTS.has(hostname);
}

export function shouldMountRemoteApp(
    search: string = window.location.search,
    hostname: string = window.location.hostname,
): boolean {
    const mode = new URLSearchParams(search.startsWith('?') ? search.slice(1) : search).get('mode');
    return mode === 'remote' && !isPublicPixelocityHost(hostname);
}
