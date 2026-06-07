#!/usr/bin/env node
/**
 * Shader Analyzer - Scans WGSL shaders and reports patterns
 * 
 * Usage: node analyze_shaders.js [shader_directory]
 */

const fs = require('fs');
const path = require('path');

const SHADER_DIR = process.argv[2] || '../public/shaders';

function analyzeShader(filePath) {
    const content = fs.readFileSync(filePath, 'utf8');
    const name = path.basename(filePath, '.wgsl');
    
    // Extract bindings
    const bindingMatches = content.matchAll(/@binding\((\d+)\)/g);
    const bindings = new Set();
    for (const match of bindingMatches) {
        bindings.add(parseInt(match[1]));
    }
    
    // Extract workgroup size
    const workgroupMatch = content.match(/@workgroup_size\(([^)]+)\)/);
    const workgroupSize = workgroupMatch ? workgroupMatch[1] : 'unknown';
    
    // Check for special patterns
    const hasTextureLoad = content.includes('textureLoad');
    const hasTextureStore = content.includes('textureStore');
    const hasTextureSample = content.includes('textureSample');
    const hasLoop = content.includes('for (') || content.includes('while (');
    const hasBranching = content.includes('if (') || content.includes('switch');
    const hasNoise = content.includes('noise') || content.includes('hash') || content.includes('random');
    const hasFBM = content.includes('fbm') || content.includes('fractal');
    const usesDepth = content.includes('readDepthTexture') || content.includes('depth');
    const usesDataTexture = content.includes('dataTexture');
    const usesExtraBuffer = content.includes('extraBuffer');
    const usesPlasmaBuffer = content.includes('plasmaBuffer');
    
    // Detect category based on content
    let category = 'unknown';
    if (content.includes('reaction') || content.includes('diffusion')) category = 'simulation';
    else if (content.includes('fluid') || content.includes('liquid') || content.includes('ripple')) category = 'fluid';
    else if (content.includes('noise') || content.includes('fbm')) category = 'generative';
    else if (content.includes('sort') || content.includes('bitonic')) category = 'sorting';
    else if (content.includes('boid') || content.includes('swarm')) category = 'agent';
    else if (content.includes('glitch') || content.includes('datamosh')) category = 'glitch';
    else if (content.includes('kaleido') || content.includes('mirror')) category = 'geometric';
    else if (content.includes('light') || content.includes('glow') || content.includes('bloom')) category = 'lighting';
    else if (content.includes('blur') || content.includes('kuwahara')) category = 'filter';
    
    return {
        name,
        bindings: Array.from(bindings).sort((a, b) => a - b),
        workgroupSize,
        features: {
            textureLoad: hasTextureLoad,
            textureStore: hasTextureStore,
            textureSample: hasTextureSample,
            loops: hasLoop,
            branching: hasBranching,
            noise: hasNoise,
            fbm: hasFBM,
            depth: usesDepth,
            dataTexture: usesDataTexture,
            extraBuffer: usesExtraBuffer,
            plasmaBuffer: usesPlasmaBuffer
        },
        category,
        lineCount: content.split('\n').length
    };
}

function main() {
    const files = fs.readdirSync(SHADER_DIR)
        .filter(f => f.endsWith('.wgsl'))
        .map(f => path.join(SHADER_DIR, f));
    
    console.log(`Analyzing ${files.length} shaders...\n`);
    
    const shaders = files.map(analyzeShader);
    
    // Statistics
    const bindingCounts = {};
    const workgroupSizes = {};
    const categories = {};
    const featureCounts = {};
    
    for (const shader of shaders) {
        // Binding usage
        const bindingCount = shader.bindings.length;
        bindingCounts[bindingCount] = (bindingCounts[bindingCount] || 0) + 1;
        
        // Workgroup sizes
        workgroupSizes[shader.workgroupSize] = (workgroupSizes[shader.workgroupSize] || 0) + 1;
        
        // Categories
        categories[shader.category] = (categories[shader.category] || 0) + 1;
        
        // Features
        for (const [feature, enabled] of Object.entries(shader.features)) {
            if (enabled) {
                featureCounts[feature] = (featureCounts[feature] || 0) + 1;
            }
        }
    }
    
    console.log('=== Binding Usage ===');
    for (const [count, num] of Object.entries(bindingCounts).sort((a, b) => b[1] - a[1])) {
        console.log(`  ${count} bindings: ${num} shaders`);
    }
    
    console.log('\n=== Workgroup Sizes ===');
    for (const [size, num] of Object.entries(workgroupSizes).sort((a, b) => b[1] - a[1])) {
        console.log(`  ${size}: ${num} shaders`);
    }
    
    console.log('\n=== Categories ===');
    for (const [cat, num] of Object.entries(categories).sort((a, b) => b[1] - a[1])) {
        console.log(`  ${cat}: ${num} shaders`);
    }
    
    console.log('\n=== Features ===');
    for (const [feature, num] of Object.entries(featureCounts).sort((a, b) => b[1] - a[1])) {
        console.log(`  ${feature}: ${num} shaders`);
    }
    
    // Find shaders using special features
    console.log('\n=== Shaders Using Extra Buffer (binding 10) ===');
    const extraBufferShaders = shaders.filter(s => s.features.extraBuffer);
    console.log(`  Count: ${extraBufferShaders.length}`);
    console.log(`  Examples: ${extraBufferShaders.slice(0, 5).map(s => s.name).join(', ')}...`);
    
    console.log('\n=== Shaders Using Plasma Buffer (binding 12) ===');
    const plasmaShaders = shaders.filter(s => s.features.plasmaBuffer);
    console.log(`  Count: ${plasmaShaders.length}`);
    console.log(`  Examples: ${plasmaShaders.slice(0, 5).map(s => s.name).join(', ')}...`);
    
    // Largest shaders
    console.log('\n=== Largest Shaders (by lines) ===');
    const largest = [...shaders].sort((a, b) => b.lineCount - a.lineCount).slice(0, 10);
    for (const shader of largest) {
        console.log(`  ${shader.name}: ${shader.lineCount} lines`);
    }
}

main();
