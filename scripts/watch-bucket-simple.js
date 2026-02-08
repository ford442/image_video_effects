#!/usr/bin/env node
/**
 * Simple GCS Bucket Watcher - No external dependencies required
 * Uses only Node.js built-in modules
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');

const CONFIG = {
    bucket: process.env.GCS_BUCKET || 'my-sd35-space-images-2025',
    imagePrefix: process.env.GCS_IMAGE_PREFIX || 'stablediff',
    videoPrefix: process.env.GCS_VIDEO_PREFIX || 'video',
    pollInterval: parseInt(process.env.GCS_POLL_INTERVAL, 10) || 30000,
    publicDir: path.join(__dirname, '..', 'public'),
    manifestPath: path.join(__dirname, '..', 'public', 'image_manifest.json'),
    videoManifestPath: path.join(__dirname, '..', 'public', 'video_manifest.json')
};

const IMAGE_EXTS = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp']);
const VIDEO_EXTS = new Set(['.mp4', '.webm', '.mov', '.mkv', '.avi']);

let lastHash = '';

function log(msg) {
    console.log(`[${new Date().toLocaleTimeString()}] ${msg}`);
}

function getUrl(bucket, blob) {
    return `https://storage.googleapis.com/${bucket}/${blob}`;
}

function parseXmlSimple(xml) {
    // Simple XML parser for GCS ListBucketResult
    const results = [];
    const keyRegex = /<Key>([^<]+)<\/Key>/g;
    let match;
    
    while ((match = keyRegex.exec(xml)) !== null) {
        const key = match[1];
        if (key.endsWith('/')) continue;
        
        const ext = path.extname(key).toLowerCase();
        if (!IMAGE_EXTS.has(ext) && !VIDEO_EXTS.has(ext)) continue;
        
        const filename = path.basename(key, ext);
        const tags = filename
            .replace(/[_-]/g, ' ')
            .split(/\s+/)
            .filter(t => t.length > 2 && !/^\d+$/.test(t))
            .map(t => t.toLowerCase());
        
        results.push({
            url: getUrl(CONFIG.bucket, key),
            path: key,
            tags: [...new Set(tags)]
        });
    }
    
    return results;
}

function fetchXml(url) {
    return new Promise((resolve, reject) => {
        https.get(url, { timeout: 30000 }, (res) => {
            if (res.statusCode !== 200) {
                reject(new Error(`HTTP ${res.statusCode}`));
                return;
            }
            let data = '';
            res.on('data', c => data += c);
            res.on('end', () => resolve(data));
        }).on('error', reject);
    });
}

async function listBlobs(prefix) {
    const url = `https://storage.googleapis.com/${CONFIG.bucket}?prefix=${encodeURIComponent(prefix)}`;
    try {
        const xml = await fetchXml(url);
        return parseXmlSimple(xml);
    } catch (e) {
        log(`Error: ${e.message}`);
        return [];
    }
}

function saveManifest(images, videos) {
    const manifest = { images, videos, updated_at: new Date().toISOString() };
    const hash = crypto.createHash('md5').update(JSON.stringify(manifest)).digest('hex');
    
    if (hash === lastHash) return false;
    lastHash = hash;
    
    if (!fs.existsSync(CONFIG.publicDir)) {
        fs.mkdirSync(CONFIG.publicDir, { recursive: true });
    }
    
    fs.writeFileSync(CONFIG.manifestPath, JSON.stringify(manifest, null, 2));
    fs.writeFileSync(CONFIG.videoManifestPath, JSON.stringify({ videos, updated_at: manifest.updated_at }, null, 2));
    
    return true;
}

async function sync() {
    log(`Scanning ${CONFIG.bucket}...`);
    
    const [images, videos] = await Promise.all([
        listBlobs(CONFIG.imagePrefix),
        listBlobs(CONFIG.videoPrefix)
    ]);
    
    if (saveManifest(images, videos)) {
        log(`Updated: ${images.length} images, ${videos.length} videos`);
    } else {
        log('No changes');
    }
}

async function watch() {
    log('Watch mode started (Ctrl+C to stop)');
    await sync();
    setInterval(sync, CONFIG.pollInterval);
}

const isWatch = process.argv.includes('--watch') || process.argv.includes('-w');

if (isWatch) {
    watch();
} else {
    sync().catch(e => { log(`Error: ${e.message}`); process.exit(1); });
}
