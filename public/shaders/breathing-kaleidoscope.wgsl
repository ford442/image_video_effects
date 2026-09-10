// ═══════════════════════════════════════════════════════════════════
//  Breathing Kaleidoscope
//  Category: visual-effects
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: High
//  Upgraded: 2026-09-09
//  Ideas: inhale vs exhale petal scale; held-breath freeze
//  A packing: ACES display RGBA
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
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hash2(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash2(i), hash2(i + vec2<f32>(1.0, 0.0)), u.x),
        mix(hash2(i + vec2<f32>(0.0, 1.0)), hash2(i + vec2<f32>(1.0, 1.0)), u.x),
        u.y
    );
}

fn fbm2(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var a = 0.5;
    var pp = p;
    for (var i = 0; i < 4; i = i + 1) {
        v = v + a * noise2(pp);
        pp = pp * 2.03 + vec2<f32>(1.7, 9.2);
        a = a * 0.5;
    }
    return v;
}

fn filmGrain(uv: vec2<f32>, t: f32) -> f32 {
    return hash2(uv * 500.0 + t) * 0.04 - 0.02;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let mouse = u.zoom_config.yz;
    let mouseDown = u.zoom_config.w;
    let aspect = resolution.x / max(resolution.y, 0.001);
    let time = u.config.x;
    let cycleSpeed = max(u.zoom_params.x, 0.01);
    let baseSegments = mix(3.0, 14.0, u.zoom_params.y);
    let rotationSpeed = u.zoom_params.z;
    let maxRotation = u.zoom_params.w;
    let audio = clamp(plasmaBuffer[0].xyz, vec3<f32>(0.0), vec3<f32>(1.0));
    let bass = audio.x;
    let mids = audio.y;
    let treble = audio.z;

    // Idea 2 — held-breath freeze: mouseDown holds phase at rest (no extraBuffer)
    let liveTime = select(time, 0.0, mouseDown > 0.5);
    let phase = liveTime * cycleSpeed * 6.28318 + bass * 3.0 * (1.0 - step(0.5, mouseDown));
    let breathWave = sin(phase);
    let breathAmp = (breathWave * 0.5 + 0.5) * (1.0 + bass * 0.5);
    let breathe = 0.65 + breathAmp * 0.35;

    let fbmTime = select(time * 0.15, 0.0, mouseDown > 0.5);
    let warp = (fbm2(uv * 3.5 + fbmTime) * 2.0 - 1.0) * 0.4 * breathAmp;
    let segments = max(2.5, baseSegments + warp);

    let center = vec2<f32>(0.5, 0.5) + (mouse - 0.5) * 0.14;
    let p = (uv - center) * vec2<f32>(aspect, 1.0);
    let dist = length(p);
    let angle = atan2(p.y, p.x);

    let rotation = liveTime * rotationSpeed * (1.0 + treble * 0.4) + (breathe - 0.825) * maxRotation * 6.28318;
    let sector = abs(fract((angle + rotation) / 6.28318 * segments) - 0.5) * 2.0;
    let edgeDist = min(sector, 1.0 - sector);

    // Idea 1 — inhale expands, exhale contracts petalWarp
    let inhale = select(-1.0, 1.0, breathWave > 0.0);
    let petalWarp = (0.92 + inhale * breathAmp * 0.18) * (1.0 + mids * 0.15);
    let kaleidoAngle = sector * 3.14159265;
    let dir = vec2<f32>(cos(kaleidoAngle), sin(kaleidoAngle));
    let warped = center + vec2<f32>(dir.x / aspect, dir.y) * dist * petalWarp;
    let sampleUV = clamp(warped, vec2<f32>(0.001), vec2<f32>(0.999));

    let src = textureSampleLevel(readTexture, u_sampler, sampleUV, 0.0);
    let baseColor = src.rgb;
    let depth = clamp(textureSampleLevel(readDepthTexture, non_filtering_sampler, sampleUV, 0.0).r, 0.0, 1.0);
    let depthFade = mix(1.0, 0.5, depth * dist * 1.5);

    let hue = fract(sector * 0.618 + liveTime * 0.03 + bass * 0.1);
    let jewel = vec3<f32>(
        0.5 + 0.5 * cos(6.28318 * hue + 0.0),
        0.5 + 0.5 * cos(6.28318 * hue + 2.094),
        0.5 + 0.5 * cos(6.28318 * hue + 4.188)
    ) * (0.25 + breathAmp * 0.2);

    let axisGlow = exp(-dist * (3.0 + mids * 2.0)) * (0.15 + breathAmp * 0.2);
    let glowColor = vec3<f32>(0.4 + treble * 0.2, 0.6 + bass * 0.15, 0.9) * axisGlow;

    let sparkle = smoothstep(0.06, 0.0, edgeDist) * treble * 0.35;
    let sparkColor = vec3<f32>(1.0, 0.92, 0.7) * sparkle;

    var finalColor = acesToneMap(baseColor * (0.65 + breathAmp * 0.25) * depthFade + jewel + glowColor + sparkColor);
    finalColor = finalColor + filmGrain(uv, time) * (1.0 - depth * 0.5);

    let lum = dot(finalColor, vec3<f32>(0.299, 0.587, 0.114));
    let alpha = clamp(lum * 0.35 + breathAmp * 0.22 + depth * 0.18 + sparkle * 0.15 + src.a * 0.2, 0.1, 0.95);
    let outDepth = clamp(depth + axisGlow * 0.05 + sparkle * 0.03, 0.0, 1.0);
    let outCol = vec4<f32>(finalColor, alpha);

    textureStore(writeTexture, coord, outCol);
    textureStore(writeDepthTexture, coord, vec4<f32>(outDepth, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, outCol);
}
