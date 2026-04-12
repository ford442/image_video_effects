import { fetchContentManifest } from './contentLoader';
import {
    BUCKET_BASE_URL,
    FALLBACK_IMAGES,
    FALLBACK_VIDEOS,
    IMAGE_MANIFEST_URL,
    LOCAL_MANIFEST_URL,
} from '../config/appConfig';

describe('fetchContentManifest', () => {
    const fetchMock = jest.fn();

    beforeEach(() => {
        fetchMock.mockReset();
        global.fetch = fetchMock as unknown as typeof fetch;
        jest.spyOn(console, 'log').mockImplementation(() => undefined);
        jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    });

    afterEach(() => {
        jest.restoreAllMocks();
    });

    it('prefers the API manifest when it is available', async () => {
        fetchMock.mockImplementation((url: RequestInfo | URL) => {
            if (url === IMAGE_MANIFEST_URL) {
                return Promise.resolve({
                    ok: true,
                    json: async () => [
                        { url: 'https://example.com/image.jpg', description: 'Neon Grid' },
                    ],
                });
            }

            if (url === LOCAL_MANIFEST_URL) {
                return Promise.resolve({
                    ok: true,
                    json: async () => ({
                        videos: [{ url: 'clips/demo.mp4' }],
                    }),
                });
            }

            return Promise.reject(new Error(`Unexpected url: ${String(url)}`));
        });

        const result = await fetchContentManifest();

        expect(result.manifest).toEqual([
            {
                url: 'https://example.com/image.jpg',
                tags: ['neon', 'grid'],
                description: 'Neon Grid',
            },
        ]);
        expect(result.videos).toEqual([`${BUCKET_BASE_URL}/clips/demo.mp4`]);
    });

    it('falls back to the local manifest and bundled defaults when needed', async () => {
        fetchMock.mockImplementation((url: RequestInfo | URL) => {
            if (url === IMAGE_MANIFEST_URL) {
                return Promise.reject(new Error('api unavailable'));
            }

            if (url === LOCAL_MANIFEST_URL) {
                return Promise.resolve({
                    ok: true,
                    json: async () => ({
                        images: [{ url: 'gallery/pulse.png', tags: ['pulse', 'glow'] }],
                        videos: [],
                    }),
                });
            }

            return Promise.reject(new Error(`Unexpected url: ${String(url)}`));
        });

        const result = await fetchContentManifest();

        expect(result.manifest).toEqual([
            {
                url: `${BUCKET_BASE_URL}/gallery/pulse.png`,
                tags: ['pulse', 'glow'],
                description: 'pulse, glow',
            },
        ]);
        expect(result.videos).toEqual(FALLBACK_VIDEOS);
    });

    it('uses bundled image and video fallbacks when both manifests fail', async () => {
        fetchMock.mockRejectedValue(new Error('offline'));

        const result = await fetchContentManifest();

        expect(result.manifest).toHaveLength(FALLBACK_IMAGES.length);
        expect(result.manifest[0]).toMatchObject({
            url: FALLBACK_IMAGES[0],
            tags: ['fallback', 'unsplash', 'demo'],
            description: 'Demo Image',
        });
        expect(result.videos).toEqual(FALLBACK_VIDEOS);
    });

    it('falls back to the local manifest when the API returns a non-array', async () => {
        fetchMock.mockImplementation((url: RequestInfo | URL) => {
            if (url === IMAGE_MANIFEST_URL) {
                return Promise.resolve({
                    ok: true,
                    json: async () => ({ error: 'unexpected object' }),
                });
            }

            if (url === LOCAL_MANIFEST_URL) {
                return Promise.resolve({
                    ok: true,
                    json: async () => ({
                        images: [{ url: 'gallery/fallback.png', tags: ['fallback'] }],
                        videos: [],
                    }),
                });
            }

            return Promise.reject(new Error(`Unexpected url: ${String(url)}`));
        });

        const result = await fetchContentManifest();

        expect(result.manifest).toEqual([
            {
                url: `${BUCKET_BASE_URL}/gallery/fallback.png`,
                tags: ['fallback'],
                description: 'fallback',
            },
        ]);
    });
});
