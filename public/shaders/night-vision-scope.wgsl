// ═══════════════════════════════════════════════════════════════════
//  Night Vision Scope
//  Category: interactive-mouse
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: MCP scintillation; bright-source blooming
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

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * .1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let resolution = u.config.zw;
    if (global_id.x >= u32(resolution.x) || global_id.y >= u32(resolution.y)) {
        return;
    }
    let coord = vec2<i32>(global_id.xy);
    var uv = vec2<f32>(global_id.xy) / resolution;
    let aspect = resolution.x / max(resolution.y, 1.0);

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;

    let scope_size = u.zoom_params.x;
    let grain_amt = u.zoom_params.y * (1.0 + mids * 0.6);
    let brightness = u.zoom_params.z + bass * 0.5;
    let scanline_str = u.zoom_params.w * (1.0 + treble * 0.4);

    let time = u.config.x;
    let rawMouse = u.zoom_config.yz;

    let hasSpringState = arrayLength(&extraBuffer) > 138u;
    var mouse = rawMouse;
    if (hasSpringState && extraBuffer[138] > 0.5) {
        mouse = vec2<f32>(extraBuffer[133], extraBuffer[134]);
    }
    if (global_id.x == 0u && global_id.y == 0u && hasSpringState) {
        var springPos = mouse;
        var springVel = vec2<f32>(extraBuffer[135], extraBuffer[136]);
        if (extraBuffer[138] <= 0.5) {
            springPos = rawMouse;
            springVel = vec2<f32>(0.0);
        } else {
            let dt = clamp(time - extraBuffer[137], 0.001, 0.05);
            let omega = 6.5;
            let accel = (rawMouse - springPos) * (omega * omega) - springVel * (2.0 * omega);
            springVel += accel * dt;
            springPos += springVel * dt;
        }
        extraBuffer[133] = springPos.x;
        extraBuffer[134] = springPos.y;
        extraBuffer[135] = springVel.x;
        extraBuffer[136] = springVel.y;
        extraBuffer[137] = time;
        extraBuffer[138] = 1.0;
    }

    let d_vec = uv - mouse;
    let d_aspect = vec2<f32>(d_vec.x * aspect, d_vec.y);
    let dist = length(d_aspect);

    let radius = 0.1 + scope_size * 0.4;
    let scope_mask = 1.0 - smoothstep(radius - 0.05, radius + 0.05, dist);

    var clickFlare = 0.0;
    let rippleCount = min(u32(u.config.y), 50u);
    for (var i = 0u; i < rippleCount; i++) {
        let rp = u.ripples[i];
        let age = time - rp.z;
        let safeAge = max(age, 0.0);
        let live = step(0.0, age) * (1.0 - step(1.8, age));
        let rd = length((uv - rp.xy) * vec2<f32>(aspect, 1.0));
        let ring = 1.0 - smoothstep(0.012, 0.045, abs(rd - safeAge * 0.30));
        clickFlare = max(clickFlare, ring * exp(-safeAge * 1.5) * live);
    }

    let distortion_str = -0.2 * scope_mask;
    let distorted_uv = uv + d_vec * distortion_str;
    var color = textureSampleLevel(readTexture, u_sampler, distorted_uv, 0.0).rgb;

    let lum = dot(color, vec3<f32>(0.299, 0.587, 0.114));
    let nv_color = vec3<f32>(0.0, 1.0, 0.0) * lum * (1.5 + brightness);

    // Idea 2 — bright-source blooming: smear neighbors above a luma knee.
    let texel = 1.0 / resolution;
    var bloom = 0.0;
    for (var k = 0; k < 4; k = k + 1) {
        let a = f32(k) * 1.5708;
        let nUV = clamp(distorted_uv + vec2<f32>(cos(a), sin(a)) * texel * 3.0, vec2<f32>(0.0), vec2<f32>(1.0));
        let nLum = dot(textureSampleLevel(readTexture, u_sampler, nUV, 0.0).rgb, vec3<f32>(0.299, 0.587, 0.114));
        bloom += max(nLum - 0.55, 0.0);
    }
    let bloomAmt = (bloom * 0.25) * (0.35 + brightness * 0.25);
    let nvBloom = nv_color + vec3<f32>(0.05, 0.55, 0.08) * bloomAmt;

    let noise = hash12(uv * 100.0 + vec2<f32>(time * 10.0, time * 20.0));
    // Idea 1 — MCP scintillation (sparse microchannel sparks).
    let scint = smoothstep(0.965, 0.995, hash12(uv * 240.0 + vec2<f32>(time * 17.0, 4.2))) * (0.35 + treble * 0.4);

    let scanBin = (u32(floor(uv.y * 96.0)) % 8u) + 1u;
    let fftScan = plasmaBuffer[scanBin].x;
    let scanline = sin(uv.y * 800.0 + time * (10.0 + fftScan * 3.0)) * 0.5 + 0.5;

    let outside_color = nvBloom * 0.3 * (0.8 + 0.4 * noise) * (0.8 + 0.2 * scanline);
    let inside_color = nvBloom * (0.9 + 0.1 * noise) * (0.95 + 0.05 * scanline);
    var final_color = mix(outside_color, inside_color, scope_mask);
    final_color += vec3<f32>(0.15, 1.0, 0.22) * scint * (0.4 + scope_mask * 0.6);

    let vign = 1.0 - length((uv - 0.5) * vec2<f32>(aspect, 1.0)) * 0.8;
    final_color = final_color * clamp(vign, 0.0, 1.0);
    final_color = mix(final_color, vec3<f32>(noise), clamp(grain_amt * 0.2, 0.0, 0.35));
    final_color = final_color * (1.0 - scanline_str * (1.0 - scanline) * 0.5);
    final_color += vec3<f32>(0.12, 1.0, 0.25) * clickFlare * (0.35 + treble * 0.25);

    final_color = max(final_color, vec3<f32>(0.0));
    let peak = max(max(final_color.r, final_color.g), final_color.b);
    final_color *= min(1.0, 1.7 / max(peak, 0.001));
    final_color = aces(final_color);

    let alpha = clamp(dot(final_color, vec3<f32>(0.299, 0.587, 0.114)) + scope_mask * 0.3 + scint * 0.2, 0.0, 1.0);
    let finalOut = vec4<f32>(final_color, alpha);
    textureStore(writeTexture, coord, finalOut);
    textureStore(dataTextureA, coord, finalOut);

    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;
    let depthOut = clamp(depth - scope_mask * (0.02 + brightness * 0.015) - clickFlare * 0.025, 0.0, 1.0);
    textureStore(writeDepthTexture, coord, vec4<f32>(depthOut, 0.0, 0.0, 0.0));
}
