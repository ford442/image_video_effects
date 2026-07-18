// ═══════════════════════════════════════════════════════════════════
//  gen-magnetic-liquid-glyphs
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, magnetic-liquid,
//            sdf, smin-blend, aces-tone-map, ign-dither, premultiplied-alpha
//  Complexity: High
//  Chunks From: warpedFBM, smin, bass_env, hue_preserve_clamp, ign
//  Created: 2026-07-17
//  By: Kimi swarm (manual completion after kimi-cli timeout)
// ═══════════════════════════════════════════════════════════════════
//  A dark ferrofluid surface that resolves almost-readable glyph runes
//  under strong bass, then shatters into auroral breakup on treble.
//  Mouse drag rotates the external magnetic field sculpting the liquid.
//  Depth drives transmission alpha: foreground metal opaque, background
//  fades so the underlying slot chain breathes through.
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
  config: vec4<f32>,       // x=Time, y=delta_time, zw=resolution
  zoom_config: vec4<f32>,  // x=zoom, yz=mouse_uv, w=mouse_down
  zoom_params: vec4<f32>,  // xyzw = user params p1…p4
  ripples: array<vec4<f32>, 50>,
};

const PI: f32 = 3.14159265359;
const TAU: f32 = 6.28318530718;

fn hash21(p: vec2<f32>) -> f32 { return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123); }
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let w = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2<f32>(1.0, 0.0)), w.x),
               mix(hash21(i + vec2<f32>(0.0, 1.0)), hash21(i + vec2<f32>(1.0, 1.0)), w.x), w.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s = 0.0; var a = 0.5; var f = 1.0;
    for (var i = 0; i < oct; i = i + 1) { s += a * valueNoise(p * f); f *= 2.0; a *= 0.5; }
    return s;
}
fn domainWarp(p: vec2<f32>, t: f32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p + vec2<f32>(0.0, t), 3), fbm(p + vec2<f32>(5.2, 1.3), 3));
    return p + q;
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}
fn rot(a: f32) -> mat2x2<f32> {
    let s = sin(a); let c = cos(a);
    return mat2x2<f32>(c, -s, s, c);
}
fn acesToneMap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 { return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715)))); }
fn huePreserveClamp(c: vec3<f32>, maxLum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    return c * min(1.0, maxLum / max(l, 1e-4));
}
fn sdSeg(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>, r: f32) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

// rune-like glyph from 3 strokes + optional dot, seeded per glyph
fn glyphD(p: vec2<f32>, seed: f32) -> f32 {
    let s = 0.085;
    var d = sdSeg(p, vec2<f32>(0.0, -s), vec2<f32>(0.0, s), 0.011);
    let a1 = (hash21(vec2<f32>(seed, 1.0)) - 0.5) * 2.6;
    let a2 = (hash21(vec2<f32>(seed, 2.0)) - 0.5) * 2.6;
    d = smin(d, sdSeg(p, vec2<f32>(0.0, s * 0.55), vec2<f32>(cos(a1), sin(a1)) * s * 1.25, 0.009), 0.028);
    d = smin(d, sdSeg(p, vec2<f32>(0.0, -s * 0.55), vec2<f32>(-cos(a2), sin(a2)) * s * 1.25, 0.009), 0.028);
    if (hash21(vec2<f32>(seed, 3.0)) > 0.5) {
        d = smin(d, length(p - vec2<f32>(0.0, s * 1.55)) - 0.026, 0.02);
    }
    return d;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - 0.5 * res) / min(res.x, res.y);
    let time = u.config.x;
    let glyphScale = mix(0.6, 1.4, u.zoom_params.x);
    let chaosBase = mix(0.2, 1.0, u.zoom_params.y);
    let emission = mix(0.3, 2.0, u.zoom_params.z);
    let hueBase = u.zoom_params.w;

    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let prev = textureLoad(dataTextureC, pixel, 0);

    // envelopes: bass resolves glyphs, treble shatters them
    let bassEnv = mix(prev.r, bass, select(0.05, 0.30, bass > prev.r));
    let trebEnv = mix(prev.g, treble, select(0.07, 0.45, treble > prev.g));

    // external magnetic field angle: mouse drag rotates, time drifts
    let fieldAngle = u.zoom_config.y * TAU * 1.5 + time * 0.12 * (1.0 + mids * 0.4);

    // domain warp: bass calms the liquid, treble rips it
    let warpAmt = mix(0.30 * chaosBase, 0.04 * chaosBase, clamp(bassEnv, 0.0, 1.0)) + trebEnv * 0.35 * chaosBase;
    let wp = uv + domainWarp(uv * 2.5, time * 0.15) * warpAmt;
    let p = rot(fieldAngle) * (wp / glyphScale);

    // glyph wheel: 6 runes on a ring + central rune, blended as liquid
    var d = glyphD(p, 7.0);
    for (var k = 0; k < 6; k = k + 1) {
        let ang = f32(k) / 6.0 * TAU;
        let gp = rot(-ang) * (p - vec2<f32>(cos(ang), sin(ang)) * 0.42);
        d = smin(d, glyphD(gp, f32(k) * 3.7 + 1.0), 0.09 + warpAmt * 0.15);
    }

    // liquid surface + edge
    let mask = smoothstep(0.012, -0.012, d);
    let edge = exp(-abs(d) * 90.0);

    // gradient normal for metal shading
    let e = vec2<f32>(0.004, 0.0);
    let gx = smoothstep(0.012, -0.012, d + e.x) - smoothstep(0.012, -0.012, d - e.x);
    let gy = smoothstep(0.012, -0.012, d + e.y) - smoothstep(0.012, -0.012, d - e.y);
    let n = normalize(vec3<f32>(-vec2<f32>(gx, gy) * 2.0, 1.0));
    let light = normalize(vec3<f32>(cos(fieldAngle), sin(fieldAngle), 0.7));
    let diff = max(dot(n, light), 0.0);
    let spec = pow(max(dot(n, normalize(light + vec3<f32>(0.0, 0.0, 1.0))), 0.0), 60.0);
    let fres = pow(1.0 - max(n.z, 0.0), 3.0);

    // dark iron liquid metal
    var col = vec3<f32>(0.02, 0.022, 0.03) + vec3<f32>(0.05, 0.055, 0.07) * diff;
    col += vec3<f32>(0.7, 0.75, 0.85) * spec * (0.6 + bassEnv);
    col += vec3<f32>(0.1, 0.35, 0.4) * fres * 0.6;

    // treble auroral breakup: emission strongest on the liquid edge
    let aur = fbm(uv * 7.0 + vec2<f32>(time * 0.4, -time * 0.3), 4);
    let aurHue = fract(hueBase + mids * 0.3 + aur * 0.4);
    let aurCol = clamp(vec3<f32>(abs(aurHue * 6.0 - 3.0) - 1.0, abs(aurHue * 6.0 - 2.0) - 1.0, abs(aurHue * 6.0 - 4.0) - 1.0),
                       vec3<f32>(0.0), vec3<f32>(1.0));
    col += aurCol * aur * trebEnv * emission * (edge * 1.6 + mask * 0.5);
    // bass resolution flash on the rune cores
    col += vec3<f32>(0.9, 0.8, 0.5) * edge * bassEnv * 0.5;

    col *= mask + edge * 0.35;
    // faint camera passthrough so the chain breathes
    let video = textureSampleLevel(readTexture, u_sampler, uv01, 0.0).rgb;
    col += video * 0.04 * (1.0 - mask);

    var outColor = acesToneMap(huePreserveClamp(col, 2.0));
    outColor = clamp(outColor + vec3<f32>((ign(vec2<f32>(pixel)) - 0.5) / 255.0), vec3<f32>(0.0), vec3<f32>(1.0));

    // transmission alpha: foreground metal opaque, background transmits
    let transmit = mix(1.0, 0.4, depth);
    let alpha = clamp(mask * transmit + edge * 0.3 * (1.0 - depth * 0.5), 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(outColor * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(mix(depth, 0.3, mask), 0.0, 0.0, 0.0));
    textureStore(dataTextureA, pixel, vec4<f32>(bassEnv, trebEnv, d, alpha));
}
