// ===============================================================
// Aurora Rift 2 – Pass 1: Volumetric Raymarch (Enhanced)
// Enhanced volumetric aurora with improved flow dynamics
// Outputs: dataTextureA (RGBA: color + density)
// ===============================================================
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

// Data texture for volumetric output to Pass 2
@group(0) @binding(13) var dataTextureA: texture_storage_2d<rgba32float, write>;

struct Uniforms {
    config:      vec4<f32>,       // x=time, y=globalIntensity, z=resX, w=resY
    zoom_params: vec4<f32>,       // x=scale, y=flowSpeed, z=diffusionRate, w=fbmOctaves
    zoom_config: vec4<f32>,       // x=rotationSpeed, y=depthParallax, z=emitThresh, w=chromaticSpread
    ripples:     array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════════════════
//  Hash functions
// ═══════════════════════════════════════════════════════════════════════════
fn hash2(p: vec2<f32>) -> f32 {
    var h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash3(p: vec3<f32>) -> f32 {
    var h = dot(p, vec3<f32>(41.0, 289.0, 57.0));
    return fract(sin(h) * 43758.5453123);
}

fn hash4(p: vec4<f32>) -> f32 {
    let dot4 = dot(p, vec4<f32>(1.0, 57.0, 113.0, 157.0));
    return fract(sin(dot4) * 43758.5453123);
}

// ═══════════════════════════════════════════════════════════════════════════
//  4-D gradient noise - LOD optimized
// ═══════════════════════════════════════════════════════════════════════════
fn noise4d(p: vec4<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    let uu = f * f * (3.0 - 2.0 * f);
    
    var sum = 0.0;
    for (var w: i32 = 0; w <= 1; w = w + 1) {
        for (var z: i32 = 0; z <= 1; z = z + 1) {
            for (var y: i32 = 0; y <= 1; y = y + 1) {
                for (var x: i32 = 0; x <= 1; x = x + 1) {
                    let corner = i + vec4<f32>(f32(x), f32(y), f32(z), f32(w));
                    let wx = select(1.0 - uu.x, uu.x, x == 1);
                    let wy = select(1.0 - uu.y, uu.y, y == 1);
                    let wz = select(1.0 - uu.z, uu.z, z == 1);
                    let ww = select(1.0 - uu.w, uu.w, w == 1);
                    let finalW = wx * wy * wz * ww;
                    sum = sum + finalW * hash4(corner);
                }
            }
        }
    }
    return sum * 2.0 - 1.0;
}

// ═══════════════════════════════════════════════════════════════════════════
//  FBM (2-D) with LOD
// ═══════════════════════════════════════════════════════════════════════════
fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        sum = sum + amp * (hash2(p * freq + time * 0.1) - 0.5);
        freq = freq * 2.0;
        amp = amp * 0.5;
    }
    return sum;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Curl noise (divergence-free)
// ═══════════════════════════════════════════════════════════════════════════
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.001;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>(n2 - n4, n1 - n3) / (2.0 * eps);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Voronoi cell distance
// ═══════════════════════════════════════════════════════════════════════════
fn voronoiCell(p: vec2<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    var best = 1e5;
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let cellPos = i + vec2<f32>(f32(x), f32(y));
            let seed = vec2<f32>(hash2(cellPos), hash2(cellPos + 13.37));
            let point = cellPos + seed - 0.5;
            let d = length(point - p);
            best = min(best, d);
        }
    }
    return best;
}

// ═══════════════════════════════════════════════════════════════════════════
//  HSV → RGB
// ═══════════════════════════════════════════════════════════════════════════
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    var c = v * s;
    let h6 = h * 6.0;
    var x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 1: Volumetric Raymarch (Enhanced)
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let time = u.config.x;
    
    // Enhanced parameters for version 2
    let scale = u.zoom_params.x * 3.0 + 1.0;
    let flowSpeed = u.zoom_params.y * 2.0 + 0.5;
    let fbmOctaves = i32(u.zoom_params.w * 5.0 + 2.0);
    let depthParallax = u.zoom_config.y * 0.6 + 0.1;
    let emitThresh = u.zoom_config.z * 0.3 + 0.1;
    
    // Sample source color & depth
    let srcCol = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    
    // Distance-based LOD
    let dist = length(uv - 0.5);
    let lodOctaves = i32(mix(f32(fbmOctaves), 2.0, smoothstep(0.3, 0.6, dist)));
    
    // Build the curl-flow field (depth-aware)
    let curl = curlNoise(uv * scale + depth * depthParallax, time * flowSpeed);
    
    // Multi-layer parallax with enhanced layering
    var totalWarp = vec2<f32>(0.0);
    var totalWeight = 0.0;
    
    // Layer 0 - foreground
    let w0 = 1.0 / (1.0 + abs(depth - 0.0) * 12.0);
    let a0 = curlNoise(uv * scale + curl * 0.3, time * flowSpeed);
    totalWarp = totalWarp + a0 * depthParallax * w0;
    totalWeight = totalWeight + w0;
    
    // Layer 1 - midground
    let w1 = 1.0 / (1.0 + abs(depth - 0.5) * 12.0);
    let a1 = curlNoise(uv * scale + curl * 0.3, time * flowSpeed * 2.0);
    totalWarp = totalWarp + a1 * depthParallax * w1;
    totalWeight = totalWeight + w1;
    
    // Layer 2 - background
    let w2 = 1.0 / (1.0 + abs(depth - 1.0) * 12.0);
    let a2 = curlNoise(uv * scale + curl * 0.3, time * flowSpeed * 3.0);
    totalWarp = totalWarp + a2 * depthParallax * w2;
    totalWeight = totalWeight + w2;
    
    totalWarp = totalWarp / max(totalWeight, 0.0001);
    
    // Voronoi + FBM hybrid (cellular foam)
    let cellDist = voronoiCell(uv * scale * 2.0 + totalWarp);
    let fbmVal = fbm(uv * scale * 4.0 + curl, time, lodOctaves);
    let foamPattern = smoothstep(0.0, 0.12, cellDist) * 0.6 + smoothstep(0.2, 0.4, fbmVal) * 0.4;
    
    // 4-D hyper-noise (depth-dependent foam surface)
    let hyper = noise4d(vec4<f32>(uv * scale * 1.5, time * 0.4, depth * 2.0));
    let hyperMod = (hyper + 1.0) * 0.5;
    
    // Phase-interference (three sinusoidal wavefronts)
    let waveA = sin(length(uv - 0.5) * 28.0 - time * 3.2);
    let waveB = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 22.0 + time * 2.7);
    let waveC = sin(dot(uv - 0.5, vec2<f32>(1.1, 0.9)) * 30.0 - time * 4.1);
    let interference = (waveA * waveB * waveC + 1.0) * 0.5;
    
    // Combine into pattern scalar
    let pattern = (foamPattern * 0.4 + hyperMod * 0.3 + interference * 0.3) *
                  (1.0 + (1.0 - depth) * 1.5);
    
    // Enhanced emissive plasma on cell borders
    let border = smoothstep(emitThresh, 1.0, smoothstep(0.08, 0.12, cellDist) * pattern * length(curl));
    let plasma = hsv2rgb(fract(time * 0.07 + pattern + hyper), 0.9, 1.0);
    
    // Enhanced aurora color with more purple/pink tones
    let auroraBase = hsv2rgb(fract(0.25 + pattern * 0.25), 0.85, 0.92);
    let auroraColor = mix(auroraBase, plasma, border * 0.6);
    
    // Enhanced density calculation
    let density = pattern * (1.0 + border * 2.5);
    
    // Pack volumetric data: RGB = color, A = density
    let volumetric = vec4<f32>(auroraColor, density);
    
    // Store for Pass 2
    textureStore(dataTextureA, gid.xy, volumetric);
    
    // Pass-through
    textureStore(writeTexture, gid.xy, vec4<f32>(0.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
