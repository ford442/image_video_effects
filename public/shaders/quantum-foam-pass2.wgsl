// ===============================================================
// Quantum Foam – Pass 2: Particle Advection
// Advects particles through the quantum field generated in Pass 1
// Inputs: dataTextureA (field from Pass 1)
// Outputs: dataTextureB (particle RGBA)
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
//  Fractal Brownian Motion
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
//  HSV to RGB
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
//  Quaternion rotation for 4D color space
// ═══════════════════════════════════════════════════════════════════════════
fn quaternionRotate(color: vec3<f32>, angle: f32, axis: vec3<f32>) -> vec3<f32> {
    var c = cos(angle);
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

// ═══════════════════════════════════════════════════════════════════════════
//  Spectral power distribution
// ═══════════════════════════════════════════════════════════════════════════
fn spectralPower(color: vec3<f32>, pattern: f32) -> vec3<f32> {
    let safeColor = max(color, vec3<f32>(0.001));
    let highPass = pow(safeColor, vec3<f32>(2.0));
    let lowPass = sqrt(safeColor);
    let bandPass = sin(safeColor * 3.14159);
    return mix(lowPass, highPass, pattern) + bandPass * pattern * 0.1;
}

// ═══════════════════════════════════════════════════════════════════════════
//  Main compute shader - PASS 2: Particle Advection
// ═══════════════════════════════════════════════════════════════════════════
@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    let uv = vec2<f32>(gid.xy) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;
    let globalIntensity = u.config.y;
    let depth = textureSampleLevel(depthTex, depthSampler, uv, 0.0).r;
    let srcColor = textureSampleLevel(videoTex, videoSampler, uv, 0.0).rgb;
    
    // Read field from Pass 1 (via dataTextureC)
    let field = textureLoad(dataTextureC, gid.xy, 0);
    let warp = field.xy;
    let pattern = field.z;
    let cellBoundary = field.w;
    
    // Parameters
    let flowSpeed = u.zoom_params.y;
    let diffusionRate = u.zoom_params.z * 0.9;
    let rotationSpeed = u.zoom_config.x * 2.0;
    let emissionThreshold = u.zoom_config.z * 0.5 + 0.3;
    let chromaticSpread = u.zoom_config.w * 2.0 + 0.5;
    
    // Recompute curl for this pass
    let foamScale = u.zoom_params.x * 3.0 + 1.0;
    let curl = curlNoise(uv * foamScale * 0.5, time * flowSpeed);
    
    // Quaternion rotation with pattern modulation
    let luminance = dot(srcColor, vec3<f32>(0.2126, 0.7152, 0.0722));
    let rotationAxis = normalize(srcColor + vec3<f32>(0.1, 0.2, 0.3));
    let rotatedColor = quaternionRotate(srcColor, time * rotationSpeed + pattern * 3.0, rotationAxis);
    
    // Chromatic dispersion with curl offsets
    let dispersion = pattern * chromaticSpread * texel * 30.0;
    let depthDispersion = depth * dispersion;
    
    // Branchless UV offsets for RGB channels
    let rUV = clamp(uv + warp * dispersion + depthDispersion + curl * 0.02, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + warp * dispersion * 0.9 + curl * 0.01, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + warp * dispersion * 1.1 - depthDispersion - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
    
    let r = textureSampleLevel(videoTex, videoSampler, rUV, 0.0).r;
    let g = textureSampleLevel(videoTex, videoSampler, gUV, 0.0).g;
    let b = textureSampleLevel(videoTex, videoSampler, bUV, 0.0).b;
    let dispersedColor = vec3<f32>(r, g, b);
    
    // Emissive quantum foam at cell boundaries
    let emission = smoothstep(emissionThreshold, 1.0, cellBoundary * pattern * luminance);
    let plasmaColor = hsv2rgb(fract(time * 0.05 + pattern), 0.9, 1.0);
    let emissiveColor = mix(dispersedColor, plasmaColor, emission * 0.5);
    
    // Temporal anisotropic diffusion
    let historyUV = clamp(uv + warp * 0.3, vec2<f32>(0.0), vec2<f32>(1.0));
    let history = textureSampleLevel(dataTextureC, videoSampler, historyUV, 0.0).rgb;
    let flowDirection = normalize(warp + curl + vec2<f32>(0.001));
    let anisotropicFactor = 1.0 - abs(dot(flowDirection, normalize(uv - 0.5 + vec2<f32>(0.001)))) * 0.3;
    let anisotropicBlend = mix(emissiveColor, history, diffusionRate * anisotropicFactor);
    
    // Spectral power distribution
    let spectralColor = spectralPower(anisotropicBlend, pattern);
    
    // Final intensity modulation
    let finalColor = mix(srcColor, spectralColor, globalIntensity);
    
    // Pack particle data for Pass 3
    // RGB = final color, A = emission intensity for glow
    let particles = vec4<f32>(finalColor, emission);
    
    // Store for Pass 3
    textureStore(dataTextureB, gid.xy, particles);
    
    // Update history buffer (via dataTextureA)
    textureStore(dataTextureA, gid.xy, vec4<f32>(anisotropicBlend, 1.0));
    
    // Pass-through color (Pass 3 will do final compositing)
    textureStore(writeTexture, gid.xy, vec4<f32>(0.0));
    textureStore(writeDepthTexture, gid.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
