// ═══════════════════════════════════════════════════════════════════
//  Digital Decay RGBA
//  Category: advanced-hybrid
//  Features: digital-decay, reaction-diffusion, rgba-state-machine
//  Complexity: Very High
//  Chunks From: digital-decay.wgsl, alpha-reaction-diffusion-rgba.wgsl
//  Created: 2026-04-18
//  By: Agent CB-13 — Retro & Glitch Enhancer
// ═══════════════════════════════════════════════════════════════════
//  Digital block corruption and chromatic aberration feed into a
//  4-species reaction-diffusion system. Corrupted pixels become
//  chemical seeds that evolve into organic decay patterns.
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

fn hash11(p: f32) -> f32 {
    var v = fract(p * 0.1031);
    v = fract(v + dot(vec2<f32>(v, v), vec2<f32>(v, v) + 33.33));
    return fract(v * v * 43758.5453);
}

fn hash21(p: vec2<f32>) -> f32 {
    var v = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    v = fract(v + dot(v, v.yzx + 33.33));
    return fract((v.x + v.y) * v.z);
}

fn hash22(p: vec2<f32>) -> vec2<f32> {
    let n = sin(vec2<f32>(dot(p, vec2<f32>(127.1, 311.7)), dot(p, vec2<f32>(269.5, 183.3))));
    return fract(n * 43758.5453);
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(gid.x) >= resolution.x || f32(gid.y) >= resolution.y) { return; }
    let uv = vec2<f32>(f32(gid.x) / resolution.x, f32(gid.y) / resolution.y);
    let time = u.config.x;
    let coord = vec2<i32>(i32(gid.x), i32(gid.y));
    let ps = 1.0 / resolution;

    let intensity = clamp(u.zoom_params.x, 0.0, 1.0);
    let rawBlock = clamp(u.zoom_params.y, 0.0, 1.0);
    let corruptionSpeed = clamp(u.zoom_params.z, 0.0, 1.0) * 5.0;
    let feed = mix(0.02, 0.06, u.zoom_params.w);

    // Read source and depth
    let src = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    // ═══ DIGITAL DECAY ═══
    let blockSizePx = floor(mix(5.0, 150.0, rawBlock));
    let blockUV = vec2<i32>(i32(floor(uv.x * resolution.x / blockSizePx)), i32(floor(uv.y * resolution.y / blockSizePx)));
    let id = f32((blockUV.x * 73856093) ^ (blockUV.y * 19349663));
    let blockHashTime = floor(time * corruptionSpeed * hash11(id + 1.0));
    let blockHash = hash21(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) + blockHashTime);

    var glitchUV = uv;
    let signalStrength = 0.55 + 0.45 * sin(time * corruptionSpeed * 0.2);
    let corruptionAmount = (1.0 - signalStrength) * intensity * 2.0;

    if (blockHash < (corruptionAmount * 0.5)) {
        let disp = (hash22(vec2<f32>(f32(blockUV.x), f32(blockUV.y)) * 99.0 + blockHashTime) - 0.5) * 0.4;
        glitchUV += disp;
    }

    let pixelHash = hash21(uv * 500.0 + time * corruptionSpeed);
    if (blockHash < (corruptionAmount * 0.2)) {
        glitchUV += (vec2<f32>(pixelHash, hash21(uv*600.0)) - 0.5) * vec2<f32>(1.0 / resolution.x, 1.0 / resolution.y) * 20.0;
    }

    let aberrationOffset = (hash22(uv + time * 0.1) - 0.5) * 0.01 * corruptionAmount;
    let r = textureSampleLevel(readTexture, u_sampler, glitchUV + aberrationOffset, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, glitchUV, 0.0).g;
    let b = textureSampleLevel(readTexture, u_sampler, glitchUV - aberrationOffset, 0.0).b;
    var decayColor = vec3<f32>(r, g, b);

    let scanLine = sin(uv.y * resolution.y * 1.5 + time) * 0.04 * corruptionAmount;
    decayColor -= scanLine;
    let noise = (hash11(dot(uv, vec2<f32>(12.9898, 78.233)) + time) - 0.5) * 0.15 * corruptionAmount;
    decayColor += noise;
    decayColor = clamp(decayColor, vec3<f32>(0.0), vec3<f32>(1.0));

    // ═══ REACTION DIFFUSION STATE ═══
    let state = textureLoad(dataTextureC, coord, 0);
    var A = state.r;
    var B = state.g;
    var C = state.b;
    var D = state.a;

    if (time < 0.1) {
        A = 1.0; B = 0.0; C = 1.0; D = 0.0;
        let centerDist = length(uv - vec2<f32>(0.5));
        if (centerDist < 0.05) { B = 0.5; D = 0.3; }
    }

    // Seed from digital decay corruption
    if (corruptionAmount > 0.3 && blockHash < corruptionAmount * 0.3) {
        B += corruptionAmount * 0.2;
        D += corruptionAmount * 0.1;
    }

    let left = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let right = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(ps.x, 0.0), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let down = textureSampleLevel(dataTextureC, u_sampler, clamp(uv - vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);
    let up = textureSampleLevel(dataTextureC, u_sampler, clamp(uv + vec2<f32>(0.0, ps.y), vec2<f32>(0.0), vec2<f32>(1.0)), 0.0);

    let lapA = left.r + right.r + down.r + up.r - 4.0 * A;
    let lapB = left.g + right.g + down.g + up.g - 4.0 * B;
    let lapC = left.b + right.b + down.b + up.b - 4.0 * C;
    let lapD = left.a + right.a + down.a + up.a - 4.0 * D;

    let kill = mix(0.04, 0.07, intensity);
    let diffA = 0.8; let diffB = 0.3; let diffC = 0.7; let diffD = 0.25;
    let crossInhibit = intensity * 0.3;
    let dt = 0.8;

    let dA = diffA * lapA - A * B * B + feed * (1.0 - A) - crossInhibit * A * D;
    let dB = diffB * lapB + A * B * B - (feed + kill) * B;
    let dC = diffC * lapC - C * D * D + feed * (1.0 - C) - crossInhibit * C * B;
    let dD = diffD * lapD + C * D * D - (feed + kill) * D;

    A = clamp(A + dA * dt, 0.0, 1.0);
    B = clamp(B + dB * dt, 0.0, 1.0);
    C = clamp(C + dC * dt, 0.0, 1.0);
    D = clamp(D + dD * dt, 0.0, 1.0);

    // Mouse injection
    let mousePos = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let mouseDist = length(uv - mousePos);
    let mouseInfluence = smoothstep(0.1, 0.0, mouseDist) * mouseDown;
    B += mouseInfluence * 0.3;
    D += mouseInfluence * 0.2;
    B = clamp(B, 0.0, 1.0);
    D = clamp(D, 0.0, 1.0);

    textureStore(dataTextureA, coord, vec4<f32>(A, B, C, D));

    // Visualization
    let colorA = vec3<f32>(0.0, 0.4, 1.0) * A;
    let colorB = vec3<f32>(1.0, 0.2, 0.0) * B;
    let colorC = vec3<f32>(0.0, 1.0, 0.3) * C;
    let colorD = vec3<f32>(1.0, 0.8, 0.0) * D;
    let rdColor = colorA + colorB + colorC + colorD;

    // Mix decay with reaction-diffusion
    let finalColor = mix(decayColor, rdColor, intensity * 0.6);

    textureStore(writeTexture, coord, vec4<f32>(finalColor, A + C));

    textureStore(writeDepthTexture, coord, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
