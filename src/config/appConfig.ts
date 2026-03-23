import { SlotParams } from '../renderer/types';

export const WEBCAM_FUN_SHADERS = [
    'liquid', 'liquid-chrome-ripple', 'liquid-rainbow', 'liquid-swirl',
    'neon-pulse', 'neon-edge-pulse', 'neon-fluid-warp', 'neon-warp',
    'vortex', 'vortex-distortion', 'vortex-warp', 'chroma-vortex',
    'distortion', 'chromatic-folds', 'holographic-projection', 'cyber-glitch-hologram',
    'kaleidoscope', 'kaleido-scope', 'fractal-kaleidoscope', 'astral-kaleidoscope',
    'rgb-fluid', 'rgb-ripple-distortion', 'rgb-shift-brush',
    'pixel-sorter', 'pixel-sort-glitch', 'ascii-shockwave',
    'magnetic-field', 'magnetic-pixels', 'magnetic-rgb'
];

export const DEPTH_MODEL_ID = 'Xenova/dpt-hybrid-midas';
export const API_BASE_URL = 'https://ford442-storage-manager.hf.space';
export const SHADER_WGSL_URL = `${API_BASE_URL}/api/shaders`;
export const IMAGE_MANIFEST_URL = `${API_BASE_URL}/api/songs?type=image`;
export const LOCAL_MANIFEST_URL = './image_manifest.json';
export const BUCKET_BASE_URL = 'https://storage.googleapis.com/my-sd35-space-images-2025';
export const IMAGE_SUGGESTIONS_URL = '/image_suggestions.md';

export const FALLBACK_IMAGES = [
    'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?q=80&w=2564&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?q=80&w=2568&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1550684848-fac1c5b4e853?q=80&w=2670&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1534447677768-be436bb09401?q=80&w=2694&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1475924156734-496f6cac6ec1?q=80&w=2670&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1614850523060-8da1d56ae167?q=80&w=2670&auto=format&fit=crop',
    'https://images.unsplash.com/photo-1605218427306-633ba8546381?q=80&w=2669&auto=format&fit=crop'
];

export const FALLBACK_VIDEOS = [
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackOnStreetAndDirt.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/VolkswagenGTIReview.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WeAreGoingOnBullrun.mp4',
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/WhatCarCanYouGetForAGrand.mp4'
];

export const DEFAULT_SLOT_PARAMS: SlotParams = {
    zoomParam1: 0.99,
    zoomParam2: 1.01,
    zoomParam3: 0.5,
    zoomParam4: 0.5,
    lightStrength: 1.0,
    ambient: 0.2,
    normalStrength: 0.1,
    fogFalloff: 4.0,
    depthThreshold: 0.5,
};
