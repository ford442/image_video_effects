// ═══════════════════════════════════════════════════════════════════
//  Radiating Displacement
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: spatial radiate from mouse; phase-split RGB of the same wave
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

fn rgb2hsv(c: vec3<f32>) -> vec3<f32> {
    let K = vec4<f32>(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    var p = mix(vec4<f32>(c.bg, K.wz), vec4<f32>(c.gb, K.xy), step(c.b, c.g));
    let q = mix(vec4<f32>(p.xyw, c.r), vec4<f32>(c.r, p.yzx), step(p.x, c.r));
    var d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn waveDisplacement(uv: vec2<f32>, centre: vec2<f32>, time: f32,
                    speed: f32, strength: f32, radius: f32, phase: f32) -> vec2<f32> {
    let delta = uv - centre;
    let dist = length(delta);
    var wave = sin((dist - time * speed) * 20.0 + phase) * 0.5 + 0.5;
    let mask = smoothstep(radius, 0.0, dist) * smoothstep(0.2, 0.8, wave);
    let dir = delta / max(dist, 0.0001);
    return dir * mask * strength * 0.02;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(gid.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    let src4 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let src = src4.rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let speed = u.zoom_params.x * 0.5 * (1.0 + bass * 0.2);
    let strength = u.zoom_params.y;
    let satThresh = u.zoom_params.z * 0.4 + 0.2;
    let radius = u.zoom_params.w * 0.15 + 0.08;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));

    let hsv = rgb2hsv(src);
    let isNeutral = (hsv.y < satThresh) || (hsv.z < 0.15) ||
                    ((hsv.x > 0.08) && (hsv.x < 0.15) && (hsv.y < 0.5));

    var displacement = vec2<f32>(0.0);
    // Idea 1 — real radial wave from the cursor (HEAD used centre=uv so dist=0)
    if (!isNeutral) {
        displacement += waveDisplacement(uv, mouse, time, speed, strength, radius, 0.0);
    }

    let rippleCount = min(u32(u.config.y), 50u);
    for (var i: u32 = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        if (age > 0.0 && age < 3.0) {
            var d = length(uv - ripple.xy);
            if (d > 0.0001) {
                let rippleDepth = textureSampleLevel(readDepthTexture, non_filtering_sampler, ripple.xy, 0.0).r;
                let depthFactor = 1.0 - rippleDepth;
                let rippleSpeed = mix(1.0, 2.0, depthFactor);
                let rippleAmp = mix(0.005, 0.015, depthFactor);
                var wave = sin(d * 25.0 - age * rippleSpeed);
                let falloff = 1.0 / (d * 20.0 + 1.0);
                let atten = 1.0 - smoothstep(0.0, 3.0, age);
                displacement += (uv - ripple.xy) / d * wave * rippleAmp * falloff * atten;
            }
        }
    }

    let bgFactor = 1.0 - smoothstep(0.0, 0.1, depth);
    if (bgFactor > 0.0) {
        let ambient = vec2<f32>(
            sin(uv.y * 15.0 + time * 1.2),
            cos(uv.x * 15.0 + time)
        ) * 0.004 * bgFactor;
        displacement += ambient;
    }

    var disp = select(vec2<f32>(0.0), displacement, !isNeutral);
    // Idea 2 — same wave, tiny RGB phase split
    let dispR = disp + waveDisplacement(uv, mouse, time, speed, strength * 0.35, radius, mids * 0.6) * select(0.0, 1.0, !isNeutral);
    let dispB = disp - waveDisplacement(uv, mouse, time, speed, strength * 0.35, radius, -mids * 0.6) * select(0.0, 1.0, !isNeutral);

    let uvR = clamp(uv + dispR, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvG = clamp(uv + disp, vec2<f32>(0.0), vec2<f32>(1.0));
    let uvB = clamp(uv + dispB, vec2<f32>(0.0), vec2<f32>(1.0));
    let r = textureSampleLevel(readTexture, u_sampler, uvR, 0.0).r;
    let g = textureSampleLevel(readTexture, u_sampler, uvG, 0.0).g;
    let ba = textureSampleLevel(readTexture, u_sampler, uvB, 0.0);
    let hdr = vec3<f32>(r, g, ba.b);
    let mapped = aces(hdr);
    let mag = length(disp) * 40.0;
    let alpha = clamp(src4.a * 0.45 + mag * 0.4 + select(0.0, 0.2, !isNeutral), 0.0, 1.0);
    let outCol = vec4<f32>(mapped, alpha);

    let outD = textureSampleLevel(readDepthTexture, non_filtering_sampler, clamp(uv + disp, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r;
    textureStore(writeTexture, pixel, outCol);
    textureStore(dataTextureA, pixel, outCol);
    textureStore(writeDepthTexture, pixel, vec4<f32>(outD, 0.0, 0.0, 0.0));
}
