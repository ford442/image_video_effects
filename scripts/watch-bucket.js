#!/usr/bin/env node
/**
 * Watch Google Cloud Storage bucket for changes and update manifests.
 * This script uses the public GCS XML API (no authentication required for public buckets).
 * 
 * Usage:
 *   node watch-bucket.js              # One-time sync
 *   node watch-bucket.js --watch      # Watch mode (polls every 30s)
 * 
 * Environment Variables:
 *   GCS_BUCKET          - GCS bucket name (default: my-sd35-space-images-2025)
 *   GCS_IMAGE_PREFIX    - Image folder prefix (default: stablediff)
 *   GCS_VIDEO_PREFIX    - Video folder prefix (default: videos)
 *   GCS_POLL_INTERVAL   - Polling interval in seconds (default: 30)
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');
const { parseStringPromise } = require('xml2js');

// Configuration
const CONFIG = {
    bucket: process.env.GCS_BUCKET || 'my-sd35-space-images-2025',
    imagePrefix: process.env.GCS_IMAGE_PREFIX || 'stablediff',
    videoPrefix: process.env.GCS_VIDEO_PREFIX || 'videos',
    pollInterval: parseInt(process.env.GCS_POLL_INTERVAL, 10) || 30000, // 30s in ms
    publicDir: path.join(__dirname, '..', 'public'),
    manifestPath: path.join(__dirname, '..', 'public', 'image_manifest.json'),
    videoManifestPath: path.join(__dirname, '..', 'public', 'video_manifest.json')
};

// File extensions
const IMAGE_EXTENSIONS = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']);
const VIDEO_EXTENSIONS = new Set(['.mp4', '.webm', '.mov', '.mkv', '.avi']);

let lastManifestHash = '';

function log(message) {
    const timestamp = new Date().toISOString().replace('T', ' ').slice(0, 19);
    console.log(`[${timestamp}] ${message}`);
}

function getPublicGcsUrl(bucket, blobName) {
    return `https://storage.googleapis.com/${bucket}/${blobName}`;
}

function fetchXml(url) {
    return new Promise((resolve, reject) => {
        https.get(url, { timeout: 30000 }, (res) => {
            if (res.statusCode !== 200) {
                reject(new Error(`HTTP ${res.statusCode}: ${res.statusMessage}`));
                return;
            }
            
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(data));
        }).on('error', reject);
    });
}

function extractTags(filename) {
    const nameWithoutExt = path.basename(filename, path.extname(filename));
    const tags = nameWithoutExt
        .replace(/[_-]/g, ' ')
        .split(/\s+/)
        .filter(t => t.length > 2 && !/^\d+$/.test(t))
        .map(t => t.toLowerCase());
    return [...new Set(tags)]; // Remove duplicates
}

async function listBlobs(bucket, prefix) {
    const url = `https://storage.googleapis.com/${bucket}?prefix=${encodeURIComponent(prefix)}`;
    
    try {
        const xml = await fetchXml(url);
        const parsed = await parseStringPromise(xml);
        
        const contents = parsed.ListBucketResult?.Contents || [];
        const results = [];
        
        for (const item of contents) {
            const key = item.Key?.[0];
            if (!key || key.endsWith('/')) continue;
            
            const ext = path.extname(key).toLowerCase();
            if (!IMAGE_EXTENSIONS.has(ext) && !VIDEO_EXTENSIONS.has(ext)) continue;
            
            results.push({
                url: getPublicGcsUrl(bucket, key),
                path: key,
                tags: extractTags(key)
            });
        }
        
        return results;
    } catch (error) {
        log(`Error listing blobs: ${error.message}`);
        if (error.message.includes('403')) {
            log('Bucket may not be public. Check bucket permissions.');
        }
        return [];
    }
}

function computeHash(data) {
    return crypto.createHash('md5').update(JSON.stringify(data)).digest('hex');
}

function saveManifest(images, videos) {
    const manifest = {
        images,
        videos,
        updated_at: new Date().toISOString()
    };
    
    const currentHash = computeHash(manifest);
    if (currentHash === lastManifestHash) {
        return false; // No changes
    }
    
    lastManifestHash = currentHash;
    
    // Ensure public directory exists
    if (!fs.existsSync(CONFIG.publicDir)) {
        fs.mkdirSync(CONFIG.publicDir, { recursive: true });
    }
    
    // Save combined manifest
    fs.writeFileSync(CONFIG.manifestPath, JSON.stringify(manifest, null, 2));
    
    // Save video-only manifest
    const videoManifest = {
        videos,
        updated_at: new Date().toISOString()
    };
    fs.writeFileSync(CONFIG.videoManifestPath, JSON.stringify(videoManifest, null, 2));
    
    return true;
}

async function syncBucket() {
    log(`Scanning bucket: ${CONFIG.bucket}`);
    
    const [images, videos] = await Promise.all([
        listBlobs(CONFIG.bucket, CONFIG.imagePrefix),
        listBlobs(CONFIG.bucket, CONFIG.videoPrefix)
    ]);
    
    log(`Found ${images.length} images, ${videos.length} videos`);
    
    if (saveManifest(images, videos)) {
        log(`Updated manifests`);
    } else {
        log('No changes detected');
    }
    
    return { images: images.length, videos: videos.length };
}

async function watchMode() {
    log(`Starting watch mode (polling every ${CONFIG.pollInterval}ms)...`);
    log('Press Ctrl+C to stop');
    
    // Initial sync
    await syncBucket();
    
    // Watch for changes
    setInterval(async () => {
        try {
            await syncBucket();
        } catch (error) {
            log(`Error during sync: ${error.message}`);
        }
    }, CONFIG.pollInterval);
}

// CLI
const args = process.argv.slice(2);
const isWatch = args.includes('--watch') || args.includes('-w');

if (isWatch) {
    watchMode().catch(error => {
        log(`Fatal error: ${error.message}`);
        process.exit(1);
    });
} else {
    syncBucket().then(({ images, videos }) => {
        log(`Sync complete: ${images} images, ${videos} videos`);
    }).catch(error => {
        log(`Error: ${error.message}`);
        process.exit(1);
    });
}
