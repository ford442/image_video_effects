// ═══════════════════════════════════════════════════════════════════
//  hyb-neural-voronoi-feedback
//  Category: hybrid
//  Features: voronoi, fbm-noise, feedback-decay, neural-dust,
//            alpha-passthrough, depth-passthrough
//  Chunks: voronoi2D + fbm2 + glow + iridescence
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

// ── Chunk: hash12 (from gen_grid.wgsl) ──
fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// ── Chunk: hash22 (from voronoi-glass.wgsl) ──
fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// ── Chunk: valueNoise (from gen_grid.wgsl) ──
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    let a = hash12(i + vec2<f32>(0.0, 0.0));
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// ── Chunk: fbm2 (from gen_grid.wgsl) ──
fn fbm2(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 1.0;
    for (var i: i32 = 0; i < octaves; i = i + 1) {
        value = value + amplitude * valueNoise(p * frequency);
        amplitude = amplitude * 0.5;
        frequency = frequency * 2.0;
    }
    return value;
}

// ── Chunk: voronoi2D (from interactive-voronoi-lens.wgsl) ──
struct VoronoiResult {
    dist: f32,
    point: vec2<f32>,
    cell: vec2<f32>,
};

fn voronoi2D(st: vec2<f32>, time: f32, chaos: f32) -> VoronoiResult {
    let i_st = floor(st);
    let f_st = fract(st);
    var result = VoronoiResult(1.0, vec2<f32>(0.0), vec2<f32>(0.0));
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            let neighbor = vec2<f32>(f32(x), f32(y));
            var point = hash22(i_st + neighbor);
            point = 0.5 + 0.5 * sin(time * chaos + 6.2831 * point);
            let d = length(neighbor + point - f_st);
            if (d < result.dist) {
                result.dist = d;
                result.point = point;
                result.cell = i_st + neighbor;
            }
        }
    }
    return result;
}

// ── Chunk: glow (from anamorphic-flare.wgsl) ──
fn glow(dist: f32, radius: f32, intensity: f32) -> f32 {
    return exp(-dist * dist / (radius * radius)) * intensity;
}

// ── Chunk: iridescence (from gen-holographic-fracture.wgsl) ──
fn iridescence(theta: f32, shift: f32) -> vec3<f32> {
    let t = theta * 4.0 + shift;
    return 0.5 + 0.5 * cos(vec3<f32>(t, t + 2.094, t + 4.189));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let dims = textureDimensions(writeTexture);
    let coord = vec2<i32>(gid.xy);
    let dimsI = vec2<i32>(dims);

    if (any(coord >= dimsI)) {
        return;
    }

    let uv = (vec2<f32>(coord) + 0.5) / vec2<f32>(dims);
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // Normalize zoom_params
    let time = u.config.x;
    let cellDensity = mix(4.0, 40.0, clamp(u.zoom_params.x, 0.0, 1.0));
    let drift = mix(0.0, 0.08, clamp(u.zoom_params.y, 0.0, 1.0));
    let dustAmt = mix(0.0, 1.0, clamp(u.zoom_params.z, 0.0, 1.0));
    let effectMix = mix(0.0, 1.0, clamp(u.zoom_params.w, 0.0, 1.0));

    // FBM-driven feedback drift over the input image
    let noiseBase = uv * 8.0 + vec2<f32>(time * 0.12);
    let driftNoiseA = fbm2(noiseBase, 4);
    let driftNoiseB = fbm2(noiseBase + vec2<f32>(5.3, 2.7), 4);
    let driftOffset = (vec2<f32>(driftNoiseA, driftNoiseB) - 0.5) * drift * 2.0;
    let fbUV = clamp(uv + driftOffset, vec2<f32>(0.0), vec2<f32>(1.0));
    let feedback = textureSampleLevel(readTexture, u_sampler, fbUV, 0.0);
    let decay = mix(0.3, 0.7, clamp(u.zoom_params.y, 0.0, 1.0));
    let echoRGB = mix(src.rgb, feedback.rgb, decay);

    // Animated Voronoi neural-cell pattern
    let voro = voronoi2D(uv * cellDensity, time, 0.7);
    let cellPhase = voro.dist * 6.28318 + time * 0.6 + voro.cell.x * 0.3;
    let cellEdge = 1.0 - smoothstep(0.0, 0.55, voro.dist);
    let cellCol = iridescence(sin(cellPhase) * 0.5 + 0.5, time * 0.4) * cellEdge;
    let cellGlow = glow(voro.dist, 0.22, 0.5) * cellEdge;

    // Neural dust: sparse glowing particles on a jittered grid
    let dustScale = mix(32.0, 96.0, clamp(u.zoom_params.z, 0.0, 1.0));
    let dustUV = uv * dustScale;
    let dId = floor(dustUV);
    let dRndX = hash12(dId + vec2<f32>(time * 0.05));
    let dRndY = hash12(dId + vec2<f32>(time * 0.05 + 17.0));
    let dCenter = fract(dustUV) - vec2<f32>(dRndX, dRndY);
    let dDist = length(dCenter);
    let dMask = smoothstep(0.1, 0.0, dDist) * dustAmt;
    let dCol = iridescence(dRndX + time * 0.25, dRndY * 6.28318);
    let dustRGB = dCol * dMask * 2.0;

    // Composite hybrid layer over the input
    let layerRGB = echoRGB + cellCol * 0.25 + cellGlow + dustRGB;
    let outRGB = mix(src.rgb, layerRGB, effectMix);

    textureStore(writeTexture, coord, vec4<f32>(clamp(outRGB, vec3<f32>(0.0), vec3<f32>(1.0)), src.a));
    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
