// ===============================================================
// Quantum Foam – Pass 1: Field Generation
// Generates quantum probability field with curl noise and FBM
// Outputs: dataTextureA (field RGBA)
// ===============================================================
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var writeTexture:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var writeDepthTexture:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var dataTextureA: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var dataTextureB:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var dataTextureC: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var comparison_sampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,       // x=time, y=globalIntensity, z=resX, w=resY
    zoom_params: vec4<f32>,       // x=foamScale, y=flowSpeed, z=diffusionRate, w=octaveCount
    zoom_config: vec4<f32>,       // x=rotationSpeed, y=depthParallax, z=emissionThreshold, w=chromaticSpread
    ripples:     array<vec4<f32>, 50>,
};

// ═══════════════════════════════════════════════════════════════════════════
//  Hash functions
// ═══════════════════════════════════════════════════════════════════════════
fn hash3(p: vec3<f32>) -> f32 {
    let p3 = fract(p * vec3<f32>(443.897, 441.423, 997.731));
    return fract(p3.x * p3.y * p3.z + dot(p3, p3 + 19.19));
}

fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

// ═══════════════════════════════════════════════════════════════════════════
//  4D gradient noise for hyper-dimensional structure
// ═══════════════════════════════════════════════════════════════════════════
fn noise4d(p: vec4<f32>) -> f32 {
    var i = floor(p);
    var f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    
    let n000 = hash3(i.xyz);
    let n100 = hash3(i.xyz + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = hash3(i.xyz + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = hash3(i.xyz + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = hash3(i.xyz + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = hash3(i.xyz + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = hash3(i.xyz + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = hash3(i.xyz + vec3<f32>(1.0, 1.0, 1.0));
    
    let nx00 = mix(n000, n100, u.x);
    let nx10 = mix(n010, n110, u.x);
    let nx01 = mix(n001, n101, u.x);
    let nx11 = mix(n011, n111, u.x);
    
    let nxy0 = mix(nx00, nx10, u.y);
    let nxy1 = mix(nx01, nx11, u.y);
    
    return mix(nxy0, nxy1, u.z);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Fractal Brownian Motion - LOD optimized
// ═══════════════════════════════════════════════════════════════════════════
fn fbm(p: vec2<f32>, time: f32, octaves: i32) -> f32 {
    var value = 0.0;
    var amp = 0.5;
    var freq = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amp * (hash3(vec3<f32>(p * freq, time * (1.0 + f32(i) * 0.2))) - 0.5);
        freq = freq * 2.15;
        amp = amp * 0.55;
    }
    return value;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Curl noise for divergence-free flow
// ═══════════════════════════════════════════════════════════════════════════
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>((n2 - n4) / (2.0 * eps), (n1 - n3) / (2.0 * eps));
}

// ═══════════════════════════════════════════════════════════════════════════
//  Voronoi with feature detection
// ═══════════════════════════════════════════════════════════════════════════
fn voronoi(p: vec2<f32>, time: f32) -> vec3<f32> {
    var i = floor(p);
    var f = fract(p);
    var minDist1 = 1000.0;
    var minDist2 = 1000.0;
    var minPoint = vec2<f32>(0.0);
    
    for (var y: i32 = -1; y <= 1; y = y + 1) {
        for (var x: i32 = -1; x <= 1; x = x + 1) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            let seed = hash3(vec3<f32>(i + neighbor, time * 0.1)) * 2.0 - 1.0;
            let point = neighbor + vec2<f32>(seed, seed * 0.7);
            let dist = length(point - f);
            if (dist < minDist1) {
                minDist2 = minDist1;
                minDist1 = dist;
                minPoint = vec2<f32>(seed, seed);
            } else if (dist < minDist2) {
                minDist2 = dist;
            }
        }
    }
    return vec3<f32>(minDist1, minDist2, minPoint.x);
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 1: Field Generation
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = vec2<f32>(gid.xy) / dims;
    let time = u.config.x;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    
    // Parameters
    let foamScale = u.zoom_params.x * 3.0 + 1.0;
    let flowSpeed = u.zoom_params.y;
    let octaveCount = i32(u.zoom_params.w * 4.0 + 3.0);
    let depthParallax = u.zoom_config.y * 0.2;
    
    // Distance-based LOD for octaves
    let dist = length(uv - 0.5);
    let lodOctaves = i32(mix(f32(octaveCount), 2.0, smoothstep(0.3, 0.7, dist)));
    
    // Curl noise for divergence-free flow field
    let curl = curlNoise(uv * foamScale * 0.5, time * flowSpeed);
    
    // Multi-layer parallax warp with curl advection
    var totalWarp = vec2<f32>(0.0);
    var parallaxWeight = 0.0;
    
    for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
        let layerDepth = f32(layer) * 0.33;
        let layerVelocity = 1.0 + f32(layer) * 0.5;
        let layerWeight = 1.0 / (1.0 + abs(depth - layerDepth) * 15.0);
        
        let advectedCurl = curlNoise(uv * foamScale * 0.5 + curl * layerVelocity, time * flowSpeed);
        let layerAngle = time * flowSpeed * layerVelocity + f32(layer) * 2.094;
        let layerOffset = advectedCurl * depthParallax * layerWeight + vec2<f32>(cos(layerAngle), sin(layerAngle)) * layerWeight * 0.1;
        
        let layerUV = uv + layerOffset;
        let layerNoise = fbm(layerUV * foamScale, time * layerVelocity, lodOctaves);
        
        totalWarp = totalWarp + vec2<f32>(layerNoise * layerWeight * layerVelocity);
        parallaxWeight = parallaxWeight + layerWeight;
    }
    
    totalWarp = totalWarp / max(parallaxWeight, 0.001);
    totalWarp = totalWarp + curl * 0.05;
    
    // Voronoi-FBM hybrid with feature detection
    let cell = voronoi(uv * foamScale + totalWarp * 2.0, time);
    let cellPattern = 1.0 - smoothstep(0.0, 0.08, cell.x);
    let cellBoundary = smoothstep(0.08, 0.12, cell.y - cell.x);
    let cellInterior = fbm(uv * foamScale * 5.0 + cell.z * 2.0, time, max(lodOctaves - 2, 2));
    let hybridPattern = mix(cellInterior, cellPattern, cellBoundary);
    
    // 4D hyper-noise
    let hyperNoise = noise4d(vec4<f32>(uv * foamScale * 2.0, time * 0.3, time * 0.1));
    
    // Phase interference from three wavefronts
    let wave1 = sin(length(uv - 0.5) * 25.0 - time * 4.0);
    let wave2 = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 18.0 + time * 3.0);
    let wave3 = sin(dot(uv - 0.5, vec2<f32>(1.0, 1.0)) * 30.0 - time * 5.0);
    let interference = (wave1 * wave2 * wave3 + 1.0) * 0.5;
    
    // Depth-aware pattern combination
    let depthWeight = 1.0 + (1.0 - depth) * 2.0;
    let pattern = (hybridPattern * 0.4 + interference * 0.3 + hyperNoise * 0.3) * depthWeight;
    
    // Pack field data: RGB = warp/direction + pattern, A = cell data
    let field = vec4<f32>(totalWarp.x, totalWarp.y, pattern, cellBoundary);
    
    // Store field for Pass 2
    textureStore(dataTextureA, gid.xy, field);
    
    // Pass-through input to maintain chain (Pass 2 will do final compositing)
    let inputColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0);
    textureStore(writeTexture, gid.xy, inputColor);
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
