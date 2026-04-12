import { ImageRecord } from '../AutoDJ';
import {
    BUCKET_BASE_URL,
    FALLBACK_IMAGES,
    FALLBACK_VIDEOS,
    IMAGE_MANIFEST_URL,
    LOCAL_MANIFEST_URL,
} from '../config/appConfig';

interface ApiManifestItem {
    url: string;
    description?: string;
}

interface LocalManifestItem {
    url: string;
    tags?: string[];
}

interface LocalManifestResponse {
    images?: LocalManifestItem[];
    videos?: LocalManifestItem[];
}

export interface LoadedContent {
    manifest: ImageRecord[];
    videos: string[];
}

export async function fetchContentManifest(): Promise<LoadedContent> {
    let manifest: ImageRecord[] = [];
    let videos: string[] = [];

    try {
        const response = await fetch(IMAGE_MANIFEST_URL);
        if (response.ok) {
            const data = await response.json() as ApiManifestItem[];
            if (!Array.isArray(data)) {
                throw new TypeError('API response is not an array');
            }
            manifest = data.map((item) => ({
                url: item.url,
                tags: item.description ? item.description.toLowerCase().split(/[\s,]+/) : [],
                description: item.description || '',
            }));
        }
    } catch (error) {
        console.warn('Backend API failed, trying local manifest...', error);
    }

    if (manifest.length === 0 || videos.length === 0) {
        try {
            const response = await fetch(LOCAL_MANIFEST_URL);
            if (response.ok) {
                const data = await response.json() as LocalManifestResponse;

                if (manifest.length === 0) {
                    manifest = (data.images || []).map((item) => {
                        const cleanUrl = item.url.replace('my-sd35-space-images-2025/', '');
                        return {
                            url: item.url.startsWith('http') ? item.url : `${BUCKET_BASE_URL}/${cleanUrl}`,
                            tags: item.tags || [],
                            description: item.tags ? item.tags.join(', ') : '',
                        };
                    });
                }

                if (videos.length === 0) {
                    videos = (data.videos || []).map((item) => {
                        const cleanUrl = item.url.replace('my-sd35-space-images-2025/', '');
                        return item.url.startsWith('http') ? item.url : `${BUCKET_BASE_URL}/${cleanUrl}`;
                    });
                }

                console.log('Loaded local manifest. Total:', manifest.length, 'images,', videos.length, 'videos');
            }
        } catch (error) {
            console.warn('Failed to load local manifest:', error);
        }
    }

    if (manifest.length === 0) {
        console.warn('Image manifest empty. Using robust Unsplash fallback.');
        manifest = FALLBACK_IMAGES.map((url) => ({
            url,
            tags: ['fallback', 'unsplash', 'demo'],
            description: 'Demo Image',
        }));
    }

    if (videos.length === 0) {
        console.warn('No videos found. Using sample videos.');
        videos = FALLBACK_VIDEOS;
    }

    return { manifest, videos };
}
