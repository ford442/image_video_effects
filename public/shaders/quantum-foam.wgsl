// ===============================================================
// Quantum Foam – Chromatic Parallax Diffusion
// Color fragments exist in superposition across depth planes,
// collapsing into observation through fractal interference.
// Features 4D gradient noise, curl advection, Voronoi-FBM hybrid,
// quaternion rotation, and anisotropic diffusion trails.
// ===============================================================
@group(0) @binding(0) var videoSampler: sampler;
@group(0) @binding(1) var videoTex:    texture_2d<f32>;
@group(0) @binding(2) var outTex:     texture_storage_2d<rgba32float, write>;

@group(0) @binding(3) var<uniform> u: Uniforms;
@group(0) @binding(4) var depthTex:   texture_2d<f32>;
@group(0) @binding(5) var depthSampler: sampler;
@group(0) @binding(6) var outDepth:   texture_storage_2d<r32float, write>;

@group(0) @binding(7) var historyBuf: texture_storage_2d<rgba32float, write>;
@group(0) @binding(8) var unusedBuf:  texture_storage_2d<rgba32float, write>;
@group(0) @binding(9) var historyTex: texture_2d<f32>;

@group(0) @binding(10) var<storage, read_write> extraBuffer: array<f32>;
@group(0) @binding(11) var compSampler: sampler_comparison;
@group(0) @binding(12) var<storage, read> plasmaBuffer: array<vec4<f32>>;

struct Uniforms {
    config:      vec4<f32>,       // x=time, y=globalIntensity, z=resX, w=resY
    zoom_params: vec4<f32>,       // x=foamScale, y=flowSpeed, z=diffusionRate, w=octaveCount
    zoom_config: vec4<f32>,       // x=rotationSpeed, y=depthParallax, z=emissionThreshold, w=chromaticSpread
    ripples:     array<vec4<f32>, 50>,
};

// ─────────────────────────────────────────────────────────────────────────────
//  Hash functions
// ─────────────────────────────────────────────────────────────────────────────
fn hash3(p: vec3<f32>) -> f32 {
    let p3 = fract(p * vec3<f32>(443.897, 441.423, 997.731));
    return fract(p3.x * p3.y * p3.z + dot(p3, p3 + 19.19));
}

fn hash2(p: vec2<f32>) -> f32 {
    var p2 = fract(p * vec2<f32>(123.456, 789.012));
    p2 = p2 + dot(p2, p2 + 45.678);
    return fract(p2.x * p2.y);
}

// ─────────────────────────────────────────────────────────────────────────────
//  4D gradient noise for hyper-dimensional structure
// ─────────────────────────────────────────────────────────────────────────────
fn noise4d(p: vec4<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
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

// ─────────────────────────────────────────────────────────────────────────────
//  Fractal Brownian Motion
// ─────────────────────────────────────────────────────────────────────────────
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

// ─────────────────────────────────────────────────────────────────────────────
//  Curl noise for divergence-free flow
// ─────────────────────────────────────────────────────────────────────────────
fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.01;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>((n2 - n4) / (2.0 * eps), (n1 - n3) / (2.0 * eps));
}

// ─────────────────────────────────────────────────────────────────────────────
//  Voronoi with feature detection
// ─────────────────────────────────────────────────────────────────────────────
fn voronoi(p: vec2<f32>, time: f32) -> vec3<f32> {
    let i = floor(p);
    let f = fract(p);
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

// ─────────────────────────────────────────────────────────────────────────────
//  Quaternion rotation for 4D color space
// ─────────────────────────────────────────────────────────────────────────────
fn quaternionRotate(color: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    let c = cos(angle);
    let s = sin(angle);
    let oneMinusC = 1.0 - c;
    let ax = normalize(axis);
    
    let xy = ax.x * ax.y * oneMinusC;
    let xz = ax.x * ax.z * oneMinusC;
    let yz = ax.y * ax.z * oneMinusC;
    let xs = ax.x * s;
    let ys = ax.y * s;
    let zs = ax.z * s;
    
    let m00 = ax.x * ax.x * oneMinusC + c;
    let m01 = xy + zs;
    let m02 = xz - ys;
    let m10 = xy - zs;
    let m11 = ax.y * ax.y * oneMinusC + c;
    let m12 = yz + xs;
    let m20 = xz + ys;
    let m21 = yz - xs;
    let m22 = ax.z * ax.z * oneMinusC + c;
    
    return vec3<f32>(
        color.x * m00 + color.y * m10 + color.z * m20,
        color.x * m01 + color.y * m11 + color.z * m21,
        color.x * m02 + color.y * m12 + color.z * m22
    );
}

// ─────────────────────────────────────────────────────────────────────────────
//  HSV to RGB
// ─────────────────────────────────────────────────────────────────────────────
fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0)      { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else               { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Spectral power distribution
// ─────────────────────────────────────────────────────────────────────────────
fn spectralPower(color: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.001));
    let highPass = pow(safeColor, vec3<f32>(2.0));
    let lowPass = sqrt(safeColor);
    let bandPass = sin(safeColor * 3.14159);
    return mix(lowPass, highPass, pattern) + bandPass * pattern * 0.1;
}

// ─────────────────────────────────────────────────────────────────────────────
//  Main compute shader
// ─────────────────────────────────────────────────────────────────────────────
@compute @workgroup_size(8, 8, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dimsI = textureDimensions(videoTex);
    let dims = vec2<f32>(f32(dimsI.x), f32(dimsI.y));
    if (gid.x >= u32(dimsI.x) || gid.y >= u32(dimsI.y)) {
        return;
    }

    let uv = vec2<f32>(gid.xy) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;
    let globalIntensity = u.config.y;
    
    // ────────────────────────────────────────────────────────────────────────
    //  Parameters
    // ────────────────────────────────────────────────────────────────────────
    let foamScale = u.zoom_params.x * 3.0 + 1.0;            // 1 - 4
    let flowSpeed = u.zoom_params.y;                         // 0 - 1
    let diffusionRate = u.zoom_params.z * 0.9;               // 0 - 0.9
    let octaveCount = i32(u.zoom_params.w * 4.0 + 3.0);     // 3 - 7
    let rotationSpeed = u.zoom_config.x * 2.0;               // 0 - 2
    let depthParallax = u.zoom_config.y * 0.2;               // 0 - 0.2
    let emissionThreshold = u.zoom_config.z * 0.5 + 0.3;    // 0.3 - 0.8
    let chromaticSpread = u.zoom_config.w * 2.0 + 0.5;      // 0.5 - 2.5
    
    // Sample depth and source
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    
    // ────────────────────────────────────────────────────────────────────────
    //  Curl noise for divergence-free flow field
    // ────────────────────────────────────────────────────────────────────────
    let curl = curlNoise(uv * foamScale * 0.5, time * flowSpeed);
    
    // ────────────────────────────────────────────────────────────────────────
    //  Multi-layer parallax warp with curl advection
    // ────────────────────────────────────────────────────────────────────────
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
        let layerNoise = fbm(layerUV * foamScale, time * layerVelocity, octaveCount);
        
        totalWarp = totalWarp + vec2<f32>(layerNoise * layerWeight * layerVelocity);
        parallaxWeight = parallaxWeight + layerWeight;
    }
    
    totalWarp = totalWarp / max(parallaxWeight, 0.001);
    totalWarp = totalWarp + curl * 0.05;
    
    // ────────────────────────────────────────────────────────────────────────
    //  Voronoi-FBM hybrid with feature detection
    // ────────────────────────────────────────────────────────────────────────
    let cell = voronoi(uv * foamScale + totalWarp * 2.0, time);
    let cellPattern = 1.0 - smoothstep(0.0, 0.08, cell.x);
    let cellBoundary = smoothstep(0.08, 0.12, cell.y - cell.x);
    let cellInterior = fbm(uv * foamScale * 5.0 + cell.z * 2.0, time, max(octaveCount - 2, 2));
    let hybridPattern = mix(cellInterior, cellPattern, cellBoundary);
    
    // 4D hyper-noise
    let hyperNoise = noise4d(vec4<f32>(uv * foamScale * 2.0, time * 0.3, time * 0.1));
    
    // ────────────────────────────────────────────────────────────────────────
    //  Phase interference from three wavefronts
    // ────────────────────────────────────────────────────────────────────────
    let wave1 = sin(length(uv - 0.5) * 25.0 - time * 4.0);
    let wave2 = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 18.0 + time * 3.0);
    let wave3 = sin(dot(uv - 0.5, vec2<f32>(1.0, 1.0)) * 30.0 - time * 5.0);
    let interference = (wave1 * wave2 * wave3 + 1.0) * 0.5;
    
    // Depth-aware pattern combination
    let depthWeight = 1.0 + (1.0 - depth) * 2.0;
    let pattern = (hybridPattern * 0.4 + interference * 0.3 + hyperNoise * 0.3) * depthWeight;
    
    // ────────────────────────────────────────────────────────────────────────
    //  Quaternion rotation with pattern modulation
    // ────────────────────────────────────────────────────────────────────────
    let luminance = dot(srcColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let rotationAxis = normalize(srcColor + vec3<f32>(0.1, 0.2, 0.3));
    let rotatedColor = quaternionRotate(srcColor, time * rotationSpeed + pattern * 3.0, rotationAxis);
    
    // ────────────────────────────────────────────────────────────────────────
    //  Chromatic dispersion with curl offsets
    // ────────────────────────────────────────────────────────────────────────
    let dispersion = pattern * chromaticSpread * texel * 30.0;
    let depthDispersion = depth * dispersion;
    let rUV = clamp(uv + totalWarp * dispersion + depthDispersion + curl * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + totalWarp * dispersion * 0.9 + curl * 0.01, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + totalWarp * dispersion * 1.1 - depthDispersion - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
    
    let r = textureSampleLevel(videoTex, videoSampler, rUV, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, gUV, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, bUV, 0.0).b;
    let dispersedColor = vec3<f32>(r, g, b);
    
    // ────────────────────────────────────────────────────────────────────────
    //  Emissive quantum foam at cell boundaries
    // ────────────────────────────────────────────────────────────────────────
    let emission = smoothstep(emissionThreshold, 1.0, cellBoundary * pattern * luminance);
    let plasmaColor = hsv2rgb(fract(time * 0.05 + pattern + cell.z), 0.9, 1.0);
    let emissiveColor = mix(dispersedColor, plasmaColor, emission * 0.5);
    
    // ────────────────────────────────────────────────────────────────────────
    //  Temporal anisotropic diffusion
    // ────────────────────────────────────────────────────────────────────────
    let historyUV = clamp(uv + totalWarp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let history = textureSampleLevel(historyTex, videoSampler, historyUV, 0.0).rgb;
    let flowDirection = normalize(totalWarp + curl + vec2<f32>(0.001));
    let anisotropicFactor = 1.0 - abs(dot(flowDirection, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.3;
    let anisotropicBlend = mix(emissiveColor, history, diffusionRate * anisotropicFactor);
    
    // Spectral power distribution
    let spectralColor = spectralPower(anisotropicBlend, pattern);
    
    // Final intensity modulation
    let finalColor = mix(srcColor, spectralColor, globalIntensity);
    
    // ────────────────────────────────────────────────────────────────────────
    //  Output
    // ────────────────────────────────────────────────────────────────────────
    textureStore(outTex, gid.xy, vec4<f32>(finalColor, 1.0));
    textureStore(historyBuf, gid.xy, vec4<f32>(anisotropicBlend, 1.0));
    textureStore(outDepth, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
