import { ImageRecord } from '../AutoDJ';
import { VideoRecord } from '../syncTypes';
import {
    BUCKET_BASE_URL,
    FALLBACK_IMAGES,
    FALLBACK_VIDEOS,
    IMAGE_MANIFEST_URL,
    LOCAL_MANIFEST_URL,
    VIDEO_MANIFEST_URL,
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
    videos: VideoRecord[];
}

export async function fetchContentManifest(): Promise<LoadedContent> {
    let manifest: ImageRecord[] = [];
    let videos: VideoRecord[] = [];

    // 1. Fetch images from API
    try {
        const response = await fetch(IMAGE_MANIFEST_URL);
        if (response.ok) {
            const data = await response.json() as ApiManifestItem[];
            if (!Array.isArray(data)) {
                throw new TypeError(`API response is not an array, received: ${typeof data}`);
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

    // 2. Fetch videos from API
    try {
        const response = await fetch(VIDEO_MANIFEST_URL);
        if (response.ok) {
            const data = await response.json() as any[];
            if (Array.isArray(data) && data.length > 0) {
                videos = data
                    .filter((item) => {
                        // Server-side filtering may not be active yet;
                        // only accept entries that look like videos.
                        if (item.type === 'video') return true;
                        const name = (item.name || item.title || item.filename || item.url || '').toLowerCase();
                        return /\.(mp4|webm|mov|m4v)(\?.*)?$/.test(name);
                    })
                    .map((item) => ({
                        id: item.id,
                        url: item.url || item.filename,
                        title: item.title || item.name,
                        description: item.description,
                        tags: item.tags,
                        duration: typeof item.duration === 'number' ? item.duration : undefined,
                    }));
                console.log(`Loaded ${videos.length} video(s) from ${VIDEO_MANIFEST_URL}`);
            }
        }
    } catch (error) {
        console.warn('Video manifest API failed, will try local manifest...', error);
    }

    // 3. Try Local Manifest (Bucket Images & Videos) if API Empty OR Videos Missing
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
                        return {
                            url: item.url.startsWith('http') ? item.url : `${BUCKET_BASE_URL}/${cleanUrl}`,
                        };
                    });
                }

                console.log('Loaded local manifest. Total:', manifest.length, 'images,', videos.length, 'videos');
            }
        } catch (error) {
            console.warn('Failed to load local manifest:', error);
        }
    }

    // 4. Last Resort: Fallbacks for images and videos
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
        videos = FALLBACK_VIDEOS.map((url) => ({ url }));
    }

    return { manifest, videos };
}
