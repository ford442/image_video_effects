// ═══════════════════════════════════════════════════════════════════
//  Electric Kaleidoscope Storm
//  Category: generative
//  Features: kaleidoscope, electric, storm, audio-reactive, mouse-driven, semantic-alpha
//  Complexity: Medium-High
//  Created: 2026-05-31
//  Updated: 2026-06-01
//  By: Kimi Agent (Bright batch)
// ═══════════════════════════════════════════════════════════════════

@group(0) @binding(0) var u_sampler: sampler;
@group(0) @binding(1) var readTexture: texture_2d<f32>;
@group(0) @binding(2) var writeTexture: texture_storage_2d<rgba32float, write>;
@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var readDepthTexture: texture_2d<f32>;
@group(0) @binding(5) var non_filtering_sampler: sampler;
@group(0) @binding(6) var writeDepthTexture: texture_storage_2d<r32float, write>;
@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB: texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;
@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
  config: vec4<f32>,
  zoom_config: vec4<f32>,
  zoom_params: vec4<f32>,
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;

// Noise/hash functions
fn hash1(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453123);
}

fn hash2(p: vec2<f32>) -> f32 {
    let p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    let q = p3 + dot(p3, p3.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

fn noise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash2(i);
    let b = hash2(i + vec2<f32>(1.0, 0.0));
    let c = hash2(i + vec2<f32>(0.0, 1.0));
    let d = hash2(i + vec2<f32>(1.0, 1.0));
    let u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Lightning bolt generation with jagged segments
fn lightningBolt(
    uv: vec2<f32>,
    start: vec2<f32>,
    end: vec2<f32>,
    seed: f32,
    time: f32
) -> f32 {
    let dir = end - start;
    let len = length(dir);
    let ndir = normalize(dir);
    let perp = vec2<f32>(-ndir.y, ndir.x);
    
    // Project point onto bolt line
    let toP = uv - start;
    let projT = clamp(dot(toP, ndir) / len, 0.0, 1.0);
    
    // Build jagged offset along bolt
    var offset: f32 = 0.0;
    var freq: f32 = 1.0;
    var amp: f32 = 0.08;
    
    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        offset += noise(vec2<f32>(projT * freq * 8.0 + seed * 17.0 + time * 3.0, seed * 31.0)) * amp;
        freq *= 2.5;
        amp *= 0.45;
    }
    
    // Rebuild bolt point with jaggedness
    let boltPoint = start + ndir * (projT * len) + perp * offset;
    let d = length(uv - boltPoint);
    
    // Core bolt
    let core = exp(-d * d * 800.0);
    // Glow around bolt
    let glow = exp(-d * d * 120.0) * 0.4;
    
    return core + glow;
}

// Recursive branching bolt
// Iterative (loop-based) single-chain expansion — WGSL forbids recursion.
// Original chained intensity as bolt_k * 0.6^k; color accumulated unweighted.
fn branchingBolt(
    uv: vec2<f32>,
    start: vec2<f32>,
    angle: f32,
    len: f32,
    seed: f32,
    time: f32,
    depth: i32,
    color: ptr<function, vec3<f32>>
) -> f32 {
    var curStart = start;
    var curAngle = angle;
    var curLen = len;
    var curSeed = seed;
    var curDepth = depth;
    var weight = 1.0;
    var totalIntensity = 0.0;

    loop {
        let end = curStart + vec2<f32>(cos(curAngle), sin(curAngle)) * curLen;
        let bolt = lightningBolt(uv, curStart, end, curSeed, time);

        // Bolt color intensity
        let flicker = hash1(curSeed * 7.0 + time * 20.0);
        let branchCol = vec3<f32>(
            0.3 + flicker * 0.7,
            0.7 + flicker * 0.3,
            1.0
        );

        if (flicker > 0.3) {
            *color += branchCol * bolt * (0.5 + 0.5 * flicker);
        }

        totalIntensity += bolt * weight;

        // Branch (single chain)
        if (curDepth <= 0) { break; }
        let branchSeed = curSeed + 100.0;
        let branchFlicker = hash1(branchSeed + time * 15.0);
        if (branchFlicker <= 0.5) { break; }

        let midPoint = (curStart + end) * 0.5;
        let branchAngle = curAngle + (hash1(branchSeed) - 0.5) * 1.2;
        let branchLen = curLen * (0.4 + hash1(branchSeed * 3.0) * 0.3);

        curStart = midPoint;
        curAngle = branchAngle;
        curLen = branchLen;
        curSeed = branchSeed;
        curDepth = curDepth - 1;
        weight = weight * 0.6;
    }

    return totalIntensity;
}

// Kaleidoscope sector folding
fn kaleidoscopeFold(p: vec2<f32>, sectors: f32, rotation: f32) -> vec2<f32> {
    let angle = atan2(p.y, p.x);
    let r = length(p);
    let sectorAngle = TAU / sectors;
    
    // Rotate
    let rotatedAngle = angle + rotation;
    // Fold into single sector
    let folded = fract(rotatedAngle / sectorAngle) * sectorAngle;
    // Mirror fold
    let mirrorFolded = min(folded, sectorAngle - folded);
    
    return vec2<f32>(cos(mirrorFolded), sin(mirrorFolded)) * r;
}

// Electric color palette
fn electricColor(idx: f32) -> vec3<f32> {
    if (idx < 0.33) {
        return vec3<f32>(0.0, 0.8, 1.0);  // Cyan
    } else if (idx < 0.66) {
        return vec3<f32>(1.0, 0.0, 0.8);  // Magenta
    } else {
        return vec3<f32>(1.0, 0.9, 0.0);  // Yellow
    }
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.z, u.config.w);
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    
    let time = u.config.x;
    let mousePos = (u.zoom_config.yz - res * 0.5) / min(res.x, res.y);
    let mouseDown = u.zoom_config.w > 0.5;
    let intensity = u.zoom_params.x;
    let speed = u.zoom_params.y;
    let scale = u.zoom_params.z;
    let colorShift = u.zoom_params.w;
    
    // Audio reactivity
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let audioIntensity = intensity * (1.0 + bass * 0.5);
    let audioSpeed = speed * (1.0 + mids * 0.4);
    
    // Mouse controls rotation and symmetry
    let mouseRot = atan2(mousePos.y, mousePos.x);
    let rot = time * (0.2 + audioSpeed * 0.5) + mouseRot * 0.3;
    
    // Symmetry count from mouse Y or scale param
    var sectorCount: f32 = 6.0 + floor(scale * 6.0) * 2.0;
    if (mouseDown) {
        sectorCount = 6.0 + floor((mousePos.y + 0.5) * 6.0) * 2.0;
        sectorCount = clamp(sectorCount, 4.0, 16.0);
    }
    
    // Fold into kaleidoscope
    let kp = kaleidoscopeFold(uv, sectorCount, rot);
    
    // Dark background with subtle radial gradient
    var col = vec3<f32>(0.01, 0.005, 0.015);
    
    // Background electric haze
    let bgNoise = noise(uv * 5.0 + time * 0.2);
    let bgGlow = exp(-length(uv) * length(uv) * 2.0) * bgNoise * 0.08;
    col += vec3<f32>(0.05, 0.0, 0.1) * bgGlow;
    
    // Generate lightning bolts in folded space
    var boltColor = vec3<f32>(0.0);
    
    // Main bolts radiating from center
    let numBolts = 8;
    for (var i = 0; i < numBolts; i++) {
        let fi = f32(i);
        let seed = fi * 37.0 + floor(time * (3.0 + audioSpeed * 5.0)) * 91.0;
        
        // Each bolt starts near center and goes outward
        let boltAngle = (fi / f32(numBolts)) * (TAU / sectorCount) + hash1(seed) * 0.1;
        let boltLen = 0.6 + hash1(seed * 2.0) * 0.4;
        let startR = 0.02 + hash1(seed * 5.0) * 0.05;
        let start = vec2<f32>(cos(boltAngle), sin(boltAngle)) * startR;
        
        // Rebranch depth based on intensity
        let depth = 2;
        
        let bolt = branchingBolt(
            kp, start, boltAngle, boltLen,
            seed, time, depth, &boltColor
        );
        
        // Add bolt colors
        let boltHue = fract(fi / f32(numBolts) + colorShift + time * 0.03);
        let boltCol = electricColor(boltHue);
        
        // Flickering visibility
        let flicker = hash1(seed + time * 25.0);
        let visibility = smoothstep(0.2, 0.5, flicker);
        
        col += boltCol * bolt * visibility * audioIntensity * 2.0;
        
        // Secondary smaller bolts
        if (hash1(seed * 11.0) > 0.6) {
            let seed2 = seed + 200.0;
            let bolt2 = branchingBolt(
                kp, start * 2.0, boltAngle + (hash1(seed2) - 0.5) * 0.5, boltLen * 0.6,
                seed2, time, 1, &boltColor
            );
            let secCol = electricColor(fract(boltHue + 0.5));
            col += secCol * bolt2 * visibility * 0.5 * audioIntensity;
        }
    }
    
    // Central electric orb
    let centerDist = length(kp);
    let orbGlow = exp(-centerDist * centerDist * 100.0) * (0.5 + 0.5 * sin(time * 6.0)) * (1.0 + bass * 0.3);
    col += vec3<f32>(0.8, 0.9, 1.0) * orbGlow * audioIntensity;
    
    // Energy rings from center
    let ringFreq = 4.0 + scale * 8.0;
    let rings = sin(centerDist * ringFreq - time * (3.0 + audioSpeed * 4.0)) * 0.5 + 0.5;
    let ringGlow = rings * exp(-centerDist * 3.0) * 0.2;
    col += vec3<f32>(0.2, 0.5, 0.8) * ringGlow * audioIntensity;
    
    // Random electric sparks
    let sparkSeed = floor(time * 8.0);
    for (var s = 0; s < 5; s++) {
        let fs = f32(s);
        let sparkX = hash1(sparkSeed * 13.0 + fs * 7.0) * 0.8 - 0.4;
        let sparkY = hash1(sparkSeed * 29.0 + fs * 11.0) * 0.8 - 0.4;
        let sparkPos = vec2<f32>(sparkX, sparkY);
        let sparkDist = length(kp - sparkPos);
        let sparkSize = 0.005 + hash1(fs * 3.0 + sparkSeed) * 0.01;
        let spark = exp(-sparkDist * sparkDist / (sparkSize * sparkSize));
        let sparkHue = fract(fs / 5.0 + colorShift + time * 0.05);
        col += electricColor(sparkHue) * spark * 2.0 * audioIntensity * (1.0 + treble * 0.8);
    }
    
    // Bloom/vignette
    let vignette = 1.0 - dot(uv, uv) * 0.35;
    col *= max(vignette, 0.3);
    
    // Tone mapping
    col = col / (1.0 + col * 0.3);
    
    // Neon glow color grading
    col = pow(max(col, vec3<f32>(0.0)), vec3<f32>(1.1, 1.0, 0.9));
    
    textureStore(writeTexture, pixel, vec4<f32>(col, 1.0));
}