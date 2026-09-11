// ═══════════════════════════════════════════════════════════════════
//  Hybrid Cyber-Organic
//  Category: generative
//  Features: hybrid, circuit-patterns, organic-growth, neon-glow, audio-reactive, upgraded-rgba
//  Upgraded: 2026-09-10
//  Ideas: exact-C occupancy persist; photo-luma seed on growth
//  A packing: raw occupancy in A.r; ACES on writeTexture
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

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  return clamp((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hexEdgeDist(p: vec2<f32>) -> f32 {
    var q = abs(p);
    return max(q.x * 0.5 + q.y * 0.866025, q.x);
}

fn palette(t: f32, a: vec3<f32>, b: vec3<f32>, c: vec3<f32>, d: vec3<f32>) -> vec3<f32> {
    return a + b * cos(6.28318 * (c * t + d));
}

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

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let id = vec2<i32>(global_id.xy);
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let gridSize = mix(5.0, 25.0, u.zoom_params.x);
    let growthAmount = u.zoom_params.y;
    let glowStrength = mix(0.5, 3.0, u.zoom_params.z);
    let chaosFactor = u.zoom_params.w * 0.5;

    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let srcLuma = dot(src.rgb, vec3<f32>(0.299, 0.587, 0.114));
    let prev = textureLoad(dataTextureC, id, 0);

    let aspect = resolution.x / max(resolution.y, 0.001);
    let uvCorrected = vec2<f32>(uv.x * aspect, uv.y);
    var p = uvCorrected * gridSize;

    let r = vec2<f32>(1.0, 1.7320508);
    let h = r * 0.5;
    let fractA = fract(p / r) * r - h;
    let fractB = (fract((p / r) + 0.5) * r) - h;

    var localUV = vec2<f32>(0.0);
    if (dot(fractA, fractA) < dot(fractB, fractB)) {
        localUV = fractA;
    } else {
        localUV = fractB;
    }

    var q = abs(localUV);
    let distToCenter = max(q.x * 0.5 + q.y * 0.866025, q.x);
    let distToEdge = 0.5 - distToCenter;

    let cellId = floor(p / r);
    let growthNoise = fbm2(cellId * 0.5 + time * 0.1, 3);
    let seeded = growthNoise + growthAmount - 0.5 + srcLuma * 0.45;
    let growthLive = smoothstep(0.3, 0.7, seeded);
    let occupy = max(growthLive, prev.r * mix(0.86, 0.97, growthAmount));
    let growthPattern = occupy;

    let circuitActive = growthPattern > 0.5;
    let lineThickness = mix(0.02, 0.08, growthAmount) * (1.0 + chaosFactor * hash12(cellId));
    let isHexLine = 1.0 - smoothstep(0.0, lineThickness, distToEdge);

    let tendrilNoise = fbm2(uv * gridSize * 2.0 + time * 0.2, 4);
    let tendrils = smoothstep(0.4, 0.6, tendrilNoise) * growthPattern;

    let hue = cellId.x * 0.1 + cellId.y * 0.05 + time * 0.1;
    let baseColor = palette(hue,
        vec3<f32>(0.5),
        vec3<f32>(0.5),
        vec3<f32>(1.0, 1.0, 0.5),
        vec3<f32>(0.0, 0.33, 0.67)
    );

    let cyberColor = mix(
        vec3<f32>(0.0, 0.8, 1.0),
        vec3<f32>(0.2, 1.0, 0.3),
        growthPattern
    );

    var color = vec3<f32>(0.02, 0.03, 0.05);

    if (isHexLine > 0.0 && circuitActive) {
        color = mix(color, cyberColor * glowStrength, isHexLine);
    }

    color += vec3<f32>(0.1, 0.9, 0.4) * tendrils * growthAmount;

    let glowRadius = lineThickness * 3.0;
    let glowAmt = (1.0 - smoothstep(0.0, glowRadius, distToEdge)) * growthPattern;
    color += baseColor * glowAmt * glowStrength * 0.5;

    let pulse = sin(time * 3.0 + cellId.x * 0.5 + cellId.y * 0.3 + bass * 2.0) * 0.5 + 0.5;
    color += cyberColor * pulse * isHexLine * 0.3;

    let activity = isHexLine + tendrils + glowAmt * 0.5;
    let alpha = mix(0.3, 1.0, activity);

    textureStore(dataTextureA, id, vec4<f32>(occupy, tendrils, glowAmt, 1.0));
    textureStore(writeTexture, id, vec4<f32>(acesToneMap(color), alpha));
    textureStore(writeDepthTexture, id, vec4<f32>(growthPattern, 0.0, 0.0, 0.0));
}
