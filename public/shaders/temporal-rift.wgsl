// ═══════════════════════════════════════════════════════════════════
//  Temporal Rift
//  Category: interactive-mouse
//  Features: mouse-driven, click-reactive, audio-reactive, temporal, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: distance-arrival delay; C ghost shear
//  A packing: nextHist RGBA (C is previous hist)
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn soft_ceiling(color: vec3<f32>) -> vec3<f32> {
    let positive = max(color, vec3<f32>(0.0));
    let peak = max(positive.x, max(positive.y, positive.z));
    return positive / (1.0 + max(peak - 1.0, 0.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) { return; }
    let coord = vec2<i32>(global_id.xy);
    let uv = vec2<f32>(global_id.xy) / resolution;
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let rawMouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    var mousePos = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    var mouseVelocity = vec2<f32>(extraBuffer[135], extraBuffer[136]);
    if (extraBuffer[137] < 0.5) {
        mousePos = rawMouse;
        mouseVelocity = vec2<f32>(0.0);
    }
    let dt = select(0.016, clamp(time - extraBuffer[138], 0.001, 0.05), extraBuffer[137] > 0.5);
    let omega = 10.0;
    mouseVelocity += ((rawMouse - mousePos) * (omega * omega) - mouseVelocity * (2.0 * omega)) * dt;
    mousePos += mouseVelocity * dt;
    if (global_id.x == 0u && global_id.y == 0u) {
        extraBuffer[133] = mousePos.x;
        extraBuffer[134] = mousePos.y;
        extraBuffer[135] = mouseVelocity.x;
        extraBuffer[136] = mouseVelocity.y;
        extraBuffer[137] = 1.0;
        extraBuffer[138] = time;
    }
    let mouseDown = u.zoom_config.w;

    let smearDecay = 0.9 + u.zoom_params.x * 0.09;
    let riftWidth = 0.05 + u.zoom_params.y * 0.2;
    let chromaSep = u.zoom_params.z * 0.02;
    let timeFlow = u.zoom_params.w;

    let currColor = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let aspect = resolution.x / max(resolution.y, 1.0);
    let distVec = (uv - mousePos) * vec2<f32>(aspect, 1.0);
    let dist = length(distVec);
    let rift = 1.0 - smoothstep(0.0, riftWidth, dist);
    // Idea 1 — distance-arrival delay (far pixels stay on C longer).
    let arrival = smoothstep(riftWidth * 2.4, 0.0, dist);

    var clickRift = 0.0;
    var clickShear = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i = i + 1u) {
        let ripple = u.ripples[i];
        let age = time - ripple.z;
        let live = f32(age >= 0.0 && age < 2.0);
        let delta = (uv - ripple.xy) * vec2<f32>(aspect, 1.0);
        let radius = length(delta);
        let envelope = exp(-max(age, 0.0) * 1.6) * live;
        clickRift = max(clickRift, (1.0 - smoothstep(0.0, 0.18, radius)) * envelope);
        clickShear += sin(radius * 90.0 - age * 18.0) * exp(-radius * 10.0) * envelope * 0.002;
    }

    let fftIndex = (u32(clamp(uv.y, 0.0, 0.999) * 8.0) % 8u) + 1u;
    let fftVoice = clamp(plasmaBuffer[fftIndex].x, 0.0, 1.0);
    let separation = chromaSep * (1.0 + fftVoice * 0.5) + clamp(clickShear, -0.02, 0.02);

    let histHere = textureLoad(dataTextureC, coord, 0);
    let maxC = vec2<i32>(resolution) - vec2<i32>(1);
    // Idea 2 — C ghost shear along sprung velocity.
    let shear = mouseVelocity * (0.04 + treble * 0.02);
    let shearCoord = clamp(vec2<i32>((uv + shear) * resolution), vec2<i32>(0), maxC);
    let histShear = textureLoad(dataTextureC, shearCoord, 0);
    let histRuv = clamp(coord + vec2<i32>(i32(separation * resolution.x), 0), vec2<i32>(0), maxC);
    let histBuv = clamp(coord - vec2<i32>(i32(separation * resolution.x), 0), vec2<i32>(0), maxC);
    let histR = textureLoad(dataTextureC, histRuv, 0).r;
    let histG = mix(histHere.g, histShear.g, 0.45);
    let histB = textureLoad(dataTextureC, histBuv, 0).b;
    let histColor = vec4<f32>(histR, histG, histB, currColor.a);

    let paintFactor = clamp(max(rift * (0.5 + 0.5 * mouseDown), clickRift) * (0.85 + fftVoice * 0.15) * arrival, 0.0, 1.0);
    let nextHist = mix(histColor * smearDecay, currColor, paintFactor);
    let display = aces(soft_ceiling(currColor.rgb + nextHist.rgb * timeFlow * (1.0 + bass * 0.1)));
    let alpha = clamp(currColor.a * 0.35 + nextHist.a * timeFlow + rift * 0.2 + clickRift * 0.15, 0.0, 1.0);

    textureStore(writeTexture, coord, vec4<f32>(display, alpha));
    textureStore(dataTextureA, coord, clamp(nextHist, vec4<f32>(0.0), vec4<f32>(1.0)));
    let depth_in = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    textureStore(writeDepthTexture, coord, vec4<f32>(depth_in, 0.0, 0.0, 0.0));
}
