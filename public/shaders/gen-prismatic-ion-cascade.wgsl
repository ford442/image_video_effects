// ═══════════════════════════════════════════════════════════════════
//  Prismatic Ion Cascade
//  Category: generative
//  Features: mouse-driven, audio-reactive, upgraded-rgba, chromatic-split,
//            temporal-cascade-persistence, audio-stream-modulation, depth-scaled
//  Complexity: Medium
//  Upgraded: 2026-06-06
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

fn hash21(p: vec2<f32>) -> f32 {
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453);
}

fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    let uu = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, uu.x), mix(c, d, uu.x), uu.y);
}

fn fbm(p: vec2<f32>) -> f32 {
    var v = 0.0;
    var amp = 0.5;
    var freq = p;
    for (var i = 0; i < 5; i++) {
        v += amp * noise2(freq);
        freq = freq * 2.03;
        amp = amp * 0.5;
    }
    return v;
}

fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
  let a = 2.51;
  let b = 0.03;
  let c = 2.43;
  let d = 0.59;
  let e = 0.14;
  return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (f32(global_id.x) >= resolution.x || f32(global_id.y) >= resolution.y) { return; }

    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    // Audio drives stream count dynamically
    let streamDensity = 4.0 + u.zoom_params.x * 16.0 + bass * 4.0;
    let cascadeSpeed = 0.3 + u.zoom_params.y * 2.0;
    let spectralSpread = 0.02 + u.zoom_params.z * 0.15;
    let ionThickness = 0.005 + u.zoom_params.w * 0.06;

    let mouse = vec2<f32>(u.zoom_config.y, u.zoom_config.z);
    let aspect = resolution.x / max(resolution.y, 1.0);
    let p = vec2<f32>((uv.x - mouse.x) * aspect, uv.y - mouse.y);

    let r = length(p);
    let theta = atan2(p.y, p.x);

    let warp = fbm(vec2<f32>(theta * 2.0, time * cascadeSpeed * (1.0 + mids * 0.4)));
    let bandPhase = theta * streamDensity + warp * 3.0 + time * cascadeSpeed * (1.0 + bass * 0.5);
    let bandWave = sin(bandPhase);
    let bandMask = smoothstep(1.0 - ionThickness * 20.0, 1.0, abs(bandWave));

    let radialPulse = 1.0 + bass * 0.6;
    let coreFall = exp(-r * (3.0 - radialPulse));
    let outerFall = exp(-r * 1.4);

    let split = spectralSpread * (1.0 + treble * 0.8);
    let phaseR = sin(bandPhase + split * 6.28);
    let phaseG = sin(bandPhase);
    let phaseB = sin(bandPhase - split * 6.28);

    let maskR = smoothstep(1.0 - ionThickness * 20.0, 1.0, abs(phaseR));
    let maskG = smoothstep(1.0 - ionThickness * 20.0, 1.0, abs(phaseG));
    let maskB = smoothstep(1.0 - ionThickness * 20.0, 1.0, abs(phaseB));

    let ionR = maskR * (coreFall + outerFall * 0.4);
    let ionG = maskG * (coreFall + outerFall * 0.4);
    let ionB = maskB * (coreFall + outerFall * 0.4);

    let shimmer = fbm(p * 6.0 + vec2<f32>(time * 0.5, -time * 0.7)) * 0.5 + 0.5;
    let flicker = mix(0.7, 1.3, shimmer) * (1.0 + treble * 0.4);

    var ionColor = vec3<f32>(ionR, ionG, ionB) * flicker;

    // Temporal cascade persistence: ion trail burn-in
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let trailBurn = mix(ionColor, prev * 0.92, 0.08 + bass * 0.03);
    ionColor = mix(ionColor, trailBurn, 0.5);

    let baseSample = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let haze = vec3<f32>(0.05, 0.08, 0.18) * outerFall * (1.0 + bass * 0.5);
    let composed = baseSample.rgb * 0.35 + ionColor * 2.2 + haze;

    let sparkleSeed = hash21(floor(uv * resolution * 0.5) + floor(time * 8.0));
    let sparkle = step(0.985, sparkleSeed) * bandMask * treble * 1.5;
    var finalRGB = clamp(composed + vec3<f32>(sparkle), vec3<f32>(0.0), vec3<f32>(4.0));

    // Depth-scaled ion intensity
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthScale = 0.6 + depth * 0.4;
    finalRGB = finalRGB * depthScale;

    let ionStrength = (ionR + ionG + ionB) / 3.0;
    let alpha = clamp(baseSample.a * 0.25 + ionStrength * 0.6 + coreFall * 0.3 + bass * 0.1, 0.0, 1.0);

    let depthOut = clamp(1.0 - coreFall, 0.0, 1.0);

    finalRGB = acesToneMap(finalRGB * 1.1);
    textureStore(writeTexture, coord, vec4<f32>(finalRGB, alpha));
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
    textureStore(dataTextureA, coord, vec4<f32>(finalRGB, alpha));
}
