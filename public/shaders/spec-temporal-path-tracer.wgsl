// ═══════════════════════════════════════════════════════════════════
//  spec-temporal-path-tracer
//  Category: advanced-hybrid
//  Features: temporal-accumulation, path-tracing, Monte-Carlo
//  Complexity: Very High
//  Chunks From: chunk-library (hash22)
//  Created: 2026-04-18
//  By: Agent 3C — Spectral Computation Pioneer
// ═══════════════════════════════════════════════════════════════════
//  2D Path Tracer with Temporal Accumulation
//  Casts light rays from each pixel that bounce off surfaces defined
//  by image edges/depth. Accumulates samples over time.
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

fn hash22(p: vec2<f32>) -> vec2<f32> {
    var p3 = fract(vec3<f32>(p.xyx) * vec3<f32>(0.1031, 0.1030, 0.0973));
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

fn hash11(n: f32) -> f32 {
    return fract(sin(n * 127.1) * 43758.5453);
}

fn toneMapACES(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3(0.0), vec3(1.0));
}

// Sample luminance at position
fn sampleLuma(uv: vec2<f32>) -> f32 {
    let c = textureSampleLevel(readTexture, u_sampler, uv, 0.0).rgb;
    return dot(c, vec3<f32>(0.299, 0.587, 0.114));
}

// Compute gradient magnitude as edge strength
fn edgeStrength(uv: vec2<f32>, texel: vec2<f32>) -> f32 {
    let c = sampleLuma(uv);
    let cx = sampleLuma(uv + vec2<f32>(texel.x, 0.0));
    let cy = sampleLuma(uv + vec2<f32>(0.0, texel.y));
    return abs(cx - c) + abs(cy - c);
}

// Approximate normal from edge gradient
fn edgeNormal(uv: vec2<f32>, texel: vec2<f32>) -> vec2<f32> {
    let c = sampleLuma(uv);
    let cx = sampleLuma(uv + vec2<f32>(texel.x, 0.0));
    let cy = sampleLuma(uv + vec2<f32>(0.0, texel.y));
    return normalize(vec2<f32>(c - cx, c - cy) + 1e-6);
}

struct HitResult {
    hit: bool,
    pos: vec2<f32>,
    normal: vec2<f32>,
};

fn marchToEdge(startUV: vec2<f32>, dir: vec2<f32>, texel: vec2<f32>, maxSteps: i32, threshold: f32) -> HitResult {
    var pos = startUV;
    for (var i: i32 = 0; i < maxSteps; i = i + 1) {
        pos = pos + dir * texel * 2.0;
        if (pos.x < 0.0 || pos.x > 1.0 || pos.y < 0.0 || pos.y > 1.0) {
            return HitResult(false, pos, vec2<f32>(0.0));
        }
        if (edgeStrength(pos, texel) > threshold) {
            return HitResult(true, pos, edgeNormal(pos, texel));
        }
    }
    return HitResult(false, pos, vec2<f32>(0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let res = u.config.zw;
    let uv = (vec2<f32>(gid.xy) + 0.5) / res;
    let texel = 1.0 / res;
    let time = u.config.x;

    let maxBounces = i32(mix(2.0, 5.0, u.zoom_params.x));
    let edgeThreshold = mix(0.05, 0.3, u.zoom_params.y);
    let radianceScale = mix(0.5, 2.0, u.zoom_params.z);
    let roughness = mix(0.0, 1.0, u.zoom_params.w);

    // Read previous accumulation
    let prev = textureLoad(dataTextureC, vec2<i32>(gid.xy), 0);
    var sampleCount = prev.a;

    // Reset accumulation periodically or on first frame
    if (sampleCount > 300.0 || sampleCount < 0.5) {
        sampleCount = 0.0;
    }

    // Blue-noise jittered ray direction
    let jitter = hash22(vec2<f32>(gid.xy) + vec2<f32>(sampleCount * 1.618, sampleCount * 2.618));
    let angle = jitter.x * 6.28318530718;
    var rayDir = vec2<f32>(cos(angle), sin(angle));

    // Mouse attracts light sources
    let mousePos = u.zoom_config.yz;
    if (u.zoom_config.w > 0.5) {
        let toMouse = mousePos - uv;
        rayDir = mix(rayDir, normalize(toMouse + 1e-6), 0.3);
    }

    var radiance = vec3<f32>(0.0);
    var throughput = vec3<f32>(1.0);
    var pos = uv;

    for (var bounce: i32 = 0; bounce < maxBounces; bounce = bounce + 1) {
        let hit = marchToEdge(pos, rayDir, texel, 32, edgeThreshold);

        if (!hit.hit) {
            // Sky / background contribution
            let bgColor = textureSampleLevel(readTexture, u_sampler, pos + rayDir * 0.1, 0.0).rgb;
            radiance += throughput * bgColor * 0.3;
            break;
        }

        // Sample color at hit point
        let hitColor = textureSampleLevel(readTexture, u_sampler, hit.pos, 0.0).rgb;
        radiance += throughput * hitColor * 0.4 * radianceScale;
        throughput *= hitColor * 0.6;

        // Russian roulette termination
        let rrProb = max(throughput.r, max(throughput.g, throughput.b));
        if (rrProb < 0.01) { break; }
        let rrRand = hash11(sampleCount + f32(bounce) * 7.31 + time);
        if (rrRand > rrProb) { break; }
        throughput /= rrProb;

        // Bounce with roughness perturbation
        let reflected = reflect(rayDir, hit.normal);
        let roughJitter = hash22(hit.pos * 100.0 + vec2<f32>(f32(bounce))) - 0.5;
        rayDir = normalize(reflected + roughJitter * roughness * 2.0);
        pos = hit.pos + hit.normal * texel * 2.0;
    }

    // Temporal accumulation (running average)
    let newAccum = (prev.rgb * sampleCount + radiance) / (sampleCount + 1.0);
    let newCount = sampleCount + 1.0;

    textureStore(dataTextureA, gid.xy, vec4<f32>(newAccum, newCount));

    // Tone-map for display
    let display = toneMapACES(newAccum);
    textureStore(writeTexture, gid.xy, vec4<f32>(display, 1.0));
}
