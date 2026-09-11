// ═══════════════════════════════════════════════════════════════════
//  Radiating Haze
//  Category: artistic
//  Features: mouse-driven, audio-reactive, upgraded-rgba
//  Complexity: Medium
//  Upgraded: 2026-09-09
//  Ideas: neighbor-bleed corona; mouse-origin waves
//  A packing: persist scalar in A.r. Display ACES RGB.
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
    let d = q.x - min(q.w, q.y);
    let e = 1.0e-10;
    return vec3<f32>(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

fn hsv2rgb(h: f32, s: f32, v: f32) -> vec3<f32> {
    let c = v * s;
    let h6 = h * 6.0;
    let x = c * (1.0 - abs(fract(h6) * 2.0 - 1.0));
    var rgb = vec3<f32>(0.0);
    if (h6 < 1.0) { rgb = vec3<f32>(c, x, 0.0); }
    else if (h6 < 2.0) { rgb = vec3<f32>(x, c, 0.0); }
    else if (h6 < 3.0) { rgb = vec3<f32>(0.0, c, x); }
    else if (h6 < 4.0) { rgb = vec3<f32>(0.0, x, c); }
    else if (h6 < 5.0) { rgb = vec3<f32>(x, 0.0, c); }
    else { rgb = vec3<f32>(c, 0.0, x); }
    return rgb + vec3<f32>(v - c);
}

fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}

fn satOf(uv: vec2<f32>) -> f32 {
    let c = textureSampleLevel(readTexture, u_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    return rgb2hsv(c).y;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) gid: vec3<u32>) {
    let resolution = u.config.zw;
    let pixel = vec2<i32>(gid.xy);
    if (pixel.x >= i32(resolution.x) || pixel.y >= i32(resolution.y)) { return; }

    let uv = (vec2<f32>(pixel) + 0.5) / resolution;
    let time = u.config.x;
    let texel = 1.0 / resolution;
    let dims = vec2<i32>(textureDimensions(dataTextureC));
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;

    let src4 = textureSampleLevel(readTexture, u_sampler, uv, 0.0);
    let src = src4.rgb;
    let depth = textureSampleLevel(readDepthTexture, non_filtering_sampler, uv, 0.0).r;

    let speed = u.zoom_params.x * 0.5 * (1.0 + bass * 0.25);
    let intensity = u.zoom_params.y;
    let satThresh = u.zoom_params.z * 0.4 + 0.2;
    let radius = u.zoom_params.w * 0.15;
    let mouse = clamp(u.zoom_config.yz, vec2<f32>(0.0), vec2<f32>(1.0));
    let hueBias = mids * 0.12;
    let pulseSpd = 0.35 + bass * 0.4;

    let hsv = rgb2hsv(src);
    let isNeutral = (hsv.y < satThresh) || (hsv.z < 0.15) ||
                    ((hsv.x > 0.08) && (hsv.x < 0.15) && (hsv.y < 0.5));

    var strongMask = select(0.0, 1.0, !isNeutral);
    // Idea 1 — neighbor-bleed corona
    let nSat = satOf(uv + vec2<f32>(texel.x, 0.0)) + satOf(uv - vec2<f32>(texel.x, 0.0))
             + satOf(uv + vec2<f32>(0.0, texel.y)) + satOf(uv - vec2<f32>(0.0, texel.y));
    let bleed = smoothstep(satThresh, satThresh + 0.25, nSat * 0.25);
    strongMask = max(strongMask, bleed * 0.65);

    // Idea 2 — waves from the cursor, not always screen center
    let origin = mix(vec2<f32>(0.5), mouse, 0.85);
    let dist = length(uv - origin);
    let wave = sin((dist - time * speed) * 15.0) * 0.5 + 0.5;
    let waveMask = smoothstep(0.2, 0.8, wave) * smoothstep(radius + 0.08, 0.0, dist);
    let aura = strongMask * waveMask * mix(1.0, depth, 0.45) * intensity;

    let auraHue = fract(hsv.x + hueBias + time * pulseSpd * 0.02);
    let auraCol = hsv2rgb(auraHue, 0.9, 1.0);

    let prev = textureLoad(dataTextureC, clamp(pixel, vec2<i32>(0), dims - vec2<i32>(1)), 0).r;
    let persist = max(prev * 0.92, aura);
    textureStore(dataTextureA, pixel, vec4<f32>(persist, aura, strongMask, 1.0));

    var hdr = src + auraCol * aura;
    hdr = 1.0 - (1.0 - hdr) * (1.0 - vec3<f32>(persist * 0.3));
    let mapped = aces(hdr);
    let alpha = clamp(src4.a * 0.4 + aura * 0.45 + persist * 0.25, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(mapped, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
