// ═══════════════════════════════════════════════════════════════════
//  aurora-rift-iridescence
//  Category: advanced-hybrid
//  Features: thin-film-interference, volumetric, curl-noise, raymarching
//  Complexity: Very High
//  Chunks From: aurora-rift.wgsl, spec-iridescence-engine.wgsl
//  Created: 2026-04-18
//  By: Agent CB-1 — Spectral & Physical Light Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Atmospheric curl-flow aurora blended with thin-film interference.
//  Pattern density drives film thickness, producing soap-bubble and
//  oil-slick iridescence that flows with the aurora's organic motion.
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
  config: vec4<f32>,       // x=Time, y=MouseClickCount, z=ResX, w=ResY
  zoom_config: vec4<f32>,  // x=Time, y=MouseX, z=MouseY, w=MouseDown
  zoom_params: vec4<f32>,  // x=Scale, y=FlowSpeed, z=FilmIOR, w=Intensity
  ripples: array<vec4<f32>, 50>,
};

// ═══ CHUNK: hash functions (from aurora-rift.wgsl) ═══
fn hash2(p: vec2<f32>) -> f32 {
    var h = dot(p, vec2<f32>(127.1, 311.7));
    return fract(sin(h) * 43758.5453123);
}

fn hash3(p: vec3<f32>) -> f32 {
    var h = dot(p, vec3<f32>(41.0, 289.0, 57.0));
    return fract(sin(h) * 43758.5453123);
}

// ═══ CHUNK: fbm & curl noise (from aurora-rift.wgsl) ═══
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

fn curlNoise(p: vec2<f32>, time: f32) -> vec2<f32> {
    let eps = 0.001;
    let n1 = fbm(p + vec2<f32>(eps, 0.0), time, 4);
    let n2 = fbm(p + vec2<f32>(0.0, eps), time, 4);
    let n3 = fbm(p - vec2<f32>(eps, 0.0), time, 4);
    let n4 = fbm(p - vec2<f32>(0.0, eps), time, 4);
    return vec2<f32>(n2 - n4, n1 - n3) / (2.0 * eps);
}

// ═══ CHUNK: voronoi cell (from aurora-rift.wgsl) ═══
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

// ═══ CHUNK: thin-film interference (from spec-iridescence-engine.wgsl) ═══
fn wavelengthToRGB(lambda: f32) -> vec3<f32> {
    let t = clamp((lambda - 380.0) / (700.0 - 380.0), 0.0, 1.0);
    let r = smoothstep(0.5, 0.85, t) + smoothstep(0.0, 0.2, t) * 0.2;
    let g = 1.0 - abs(t - 0.45) * 2.5;
    let b = 1.0 - smoothstep(0.0, 0.45, t);
    return max(vec3<f32>(r, g, b), vec3<f32>(0.0));
}

fn thinFilmColor(thicknessNm: f32, cosTheta: f32, filmIOR: f32) -> vec3<f32> {
    let sinTheta_t = sqrt(max(1.0 - cosTheta * cosTheta, 0.0)) / filmIOR;
    let cosTheta_t = sqrt(max(1.0 - sinTheta_t * sinTheta_t, 0.0));
    let opd = 2.0 * filmIOR * thicknessNm * cosTheta_t;
    var color = vec3<f32>(0.0);
    var sampleCount = 0.0;
    for (var lambda = 380.0; lambda <= 700.0; lambda = lambda + 20.0) {
        let phase = opd / lambda;
        let interference = cos(phase * 6.28318530718) * 0.5 + 0.5;
        color += wavelengthToRGB(lambda) * interference;
        sampleCount = sampleCount + 1.0;
    }
    return color / max(sampleCount, 1.0);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = u.config.zw;
    if (gid.x >= u32(dims.x) || gid.y >= u32(dims.y)) { return; }

    var uv = (vec2<f32>(gid.xy) + 0.5) / dims;
    let texel = 1.0 / dims;
    let time = u.config.x;

    // Parameters
    let scale = u.zoom_params.x * 3.5 + 0.5;
    let flowSpeed = u.zoom_params.y * 2.8 + 0.2;
    let filmIOR = mix(1.2, 2.4, u.zoom_params.z);
    let intensity = mix(0.3, 1.5, u.zoom_params.w);

    let srcCol = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Curl flow field
    let curl = curlNoise(uv * scale, time * flowSpeed);

    // Multi-layer parallax warp
    var totalWarp = vec2<f32>(0.0);
    var totalWeight = 0.0;
    for (var layer: i32 = 0; layer < 3; layer = layer + 1) {
        let layerDepth = f32(layer) / 2.0;
        let layerWeight = 1.0 / (1.0 + abs(depth - layerDepth) * 12.0);
        let advected = curlNoise(uv * scale + curl * 0.3, time * flowSpeed * (1.0 + f32(layer)));
        let offset = advected * 0.3 * layerWeight;
        totalWarp = totalWarp + offset * layerWeight;
        totalWeight = totalWeight + layerWeight;
    }
    totalWarp = totalWarp / max(totalWeight, 0.0001);

    // Voronoi + FBM hybrid pattern
    let cellDist = voronoiCell(uv * scale * 2.0 + totalWarp);
    let fbmVal = fbm(uv * scale * 4.0 + curl, time, 4);
    let foamPattern = smoothstep(0.0, 0.12, cellDist) * 0.6 + smoothstep(0.2, 0.4, fbmVal) * 0.4;

    // Phase interference
    let waveA = sin(length(uv - 0.5) * 28.0 - time * 3.2);
    let waveB = sin(atan2(uv.y - 0.5, uv.x - 0.5) * 22.0 + time * 2.7);
    let waveC = sin(dot(uv - 0.5, vec2<f32>(1.1, 0.9)) * 30.0 - time * 4.1);
    let interference = (waveA * waveB * waveC + 1.0) * 0.5;

    let pattern = (foamPattern * 0.4 + interference * 0.3) * (1.0 + (1.0 - depth) * 1.5);

    // ═══ Thin-film iridescence driven by aurora pattern ═══
    let toCenter = uv - vec2<f32>(0.5);
    let dist = length(toCenter);
    let cosTheta = sqrt(max(1.0 - dist * dist * 0.5, 0.01));

    // Film thickness modulated by aurora density and curl
    let noiseVal = hash2(uv * 12.0 + time * 0.1) * 0.5
                 + hash2(uv * 25.0 - time * 0.15) * 0.25;
    let filmThicknessBase = mix(250.0, 750.0, pattern);
    var thickness = filmThicknessBase * (0.7 + depth * 0.6 + noiseVal * 0.5);

    // Mouse interaction: local thickness perturbation
    let mousePos = u.zoom_config.yz;
    let isMouseDown = u.zoom_config.w > 0.5;
    if (isMouseDown) {
        let mouseDist = length(uv - mousePos);
        let mouseInfluence = exp(-mouseDist * mouseDist * 800.0);
        thickness += mouseInfluence * 300.0 * sin(time * 3.0 + mouseDist * 30.0);
    }

    let iridescent = thinFilmColor(thickness, cosTheta, filmIOR) * intensity;

    // Chromatic dispersion from aurora base
    let disp = pattern * 0.04 * texel * 28.0;
    let rUV = clamp(uv + totalWarp * disp + curl * 0.018, vec2<f32>(0.0), vec2<f32>(1.0));
    let gUV = clamp(uv + totalWarp * disp * 0.93 + curl * 0.012, vec2<f32>(0.0), vec2<f32>(1.0));
    let bUV = clamp(uv + totalWarp * disp * 1.07 - curl * 0.015, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, rUV, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, gUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, bUV, 0.0).b;
    let dispersed = vec3<f32>(r, g, b);

    // Fresnel-like blend of iridescence over dispersed base
    let fresnel = pow(1.0 - cosTheta, 3.0);
    let blended = mix(dispersed, iridescent, fresnel * 0.65);

    // Volumetric alpha from pattern density
    let density = pattern * 2.0;
    let volAlpha = 1.0 - exp(-density * 0.8);
    let depthAlpha = mix(0.3, 1.0, depth);
    let alpha = clamp(volAlpha * depthAlpha, 0.0, 1.0);

    let finalCol = mix(srcCol, blended, 0.85);

    textureStore(writeTexture, vec2<i32>(gid.xy), vec4<f32>(finalCol, alpha));
    textureStore(dataTextureA, vec2<i32>(gid.xy), vec4<f32>(iridescent, thickness / 1000.0));
    textureStore(writeDepthTexture, vec2<i32>(gid.xy), vec4<f32>(depth, 0.0, 0.0, 0.0));
}
