// ═══════════════════════════════════════════════════════════════════
//  gen-magnetic-liquid-glyphs
//  Category: generative
//  Features: audio-reactive, mouse-driven, depth-aware, magnetic-liquid
//  Complexity: High
//  Chunks From: warpedFBM, smin, bass_env, hue_preserve_clamp, ign
//  Created: 2026-07-17
//  By: Kimi Code CLI (weekly swarm)
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
    return fract(sin(dot(p, vec2<f32>(127.1, 311.7))) * 43758.5453123);
}
fn valueNoise(p: vec2<f32>) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i+vec2(1,0)), u.x),
               mix(hash21(i+vec2(0,1)), hash21(i+vec2(1,1)), u.x), u.y);
}
fn fbm(p: vec2<f32>, oct: i32) -> f32 {
    var s=0.0; var a=0.5; var f=1.0;
    for (var i=0;i<oct;i++) { s+=a*valueNoise(p*f); f*=2.0; a*=0.5; }
    return s;
}
fn domainWarp(p: vec2<f32>, strength: f32, oct: i32) -> vec2<f32> {
    let q = vec2<f32>(fbm(p, oct), fbm(p + vec2<f32>(5.2, 1.3), oct));
    return p + strength * q;
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5*(b - a)/k, 0.0, 1.0);
    return mix(b, a, h) - k*h*(1.0 - h);
}
fn aces(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51; let b = 0.03; let c = 2.43; let d = 0.59; let e = 0.14;
    return clamp((x*(a*x+b))/(x*(c*x+d)+e), vec3<f32>(0.0), vec3<f32>(1.0));
}
fn ign(p: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}
fn hue_preserve_clamp(c: vec3<f32>, max_lum: f32) -> vec3<f32> {
    let l = dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
    let s = min(1.0, max_lum / max(l, 1e-4));
    return c * s;
}
fn rot2(a: f32) -> mat2x2<f32> {
    let c = cos(a); let s = sin(a);
    return mat2x2<f32>(c, -s, s, c);
}
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a; let ba = b - a;
    let h  = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

// near-readable glyph built from smin-blended strokes
fn glyphField(p: vec2<f32>) -> f32 {
    let v1 = sdSegment(p, vec2<f32>(-0.35,  0.45), vec2<f32>(-0.35, -0.45)) - 0.08;
    let v2 = sdSegment(p, vec2<f32>( 0.35,  0.45), vec2<f32>( 0.35, -0.45)) - 0.08;
    let bar = sdSegment(p, vec2<f32>(-0.35,  0.0), vec2<f32>( 0.35,  0.0)) - 0.06;
    let dotL = length(p - vec2<f32>(-0.35, -0.55)) - 0.10;
    let dotR = length(p - vec2<f32>( 0.35,  0.55)) - 0.10;
    var d = smin(v1, v2, 0.12);
    d = smin(d, bar, 0.10);
    d = smin(d, dotL, 0.10);
    d = smin(d, dotR, 0.10);
    return d;
}
fn glyphLayer(p: vec2<f32>, t: f32, layer: f32) -> f32 {
    let scale = 1.0 + layer * 0.45;
    var q = p / scale;
    q = rot2(t * (0.2 + layer * 0.1) + layer * 1.1) * q;
    q += vec2<f32>(sin(t * 0.3 + layer), cos(t * 0.27 - layer)) * 0.05;
    let grid = vec2<f32>(2.8 + layer, 2.2 + layer * 0.7);
    let id = round(q / grid);
    q = q - grid * id;
    let h = hash21(id + vec2<f32>(layer * 7.3));
    let g = glyphField(q + vec2<f32>(h - 0.5, fract(h * 13.7) - 0.5) * 0.2);
    return g * scale;
}

@compute @workgroup_size(16, 16, 1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let pixel = vec2<i32>(global_id.xy);
    let res = vec2<f32>(u.config.zw);
    if (pixel.x >= i32(res.x) || pixel.y >= i32(res.y)) { return; }
    let uv01 = vec2<f32>(pixel) / res;
    let uv = (vec2<f32>(pixel) - res * 0.5) / min(res.x, res.y);
    let time = u.config.x;
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let depth = textureLoad(readDepthTexture, pixel, 0).r;
    let p1 = clamp(u.zoom_params.x, 0.0, 1.0);
    let p2 = clamp(u.zoom_params.y, 0.0, 1.0);
    let p3 = clamp(u.zoom_params.z, 0.0, 1.0);
    let p4 = clamp(u.zoom_params.w, 0.0, 1.0);

    // bass envelope for glyph-resolve moments
    let prevEnv = extraBuffer[0];
    let bassEnv = mix(prevEnv, bass, 0.08);
    extraBuffer[0] = bassEnv;

    // mouse drag rotates the magnetic field
    let mouse = u.zoom_config.yz - vec2<f32>(0.5);
    let mouseDown = u.zoom_config.w > 0.5;
    let fieldAngle = time * (0.15 + p3 * 0.35) + mouse.x * (2.0 + p3 * 4.0) + select(0.0, 2.5, mouseDown) * sin(time * 2.0);

    // domain warp: bass resolves, treble shatters
    let glyphStrength = smoothstep(0.35, 0.75, bassEnv) * (1.0 - treble * 0.6);
    let chaos = (treble * 1.5 + mids * 0.4) * (0.5 + p1);
    var p = uv * (0.85 + p2 * 0.4);
    p = rot2(fieldAngle) * p;
    let warp = domainWarp(p * 2.5 + time * 0.15, 0.12 + p1 * 0.35 + chaos * 0.35 - glyphStrength * 0.12, 4);
    p = p + warp;

    // layered glyph SDF composition
    var d = glyphLayer(p, time, 0.0);
    d = smin(d, glyphLayer(p, time, 1.0), 0.18 + bass * 0.12);
    d = smin(d, glyphLayer(p, time, 2.0), 0.25);
    d = smin(d, glyphLayer(p, time, 3.0), 0.35 + chaos * 0.2);

    // liquid surface mask
    let edge = 0.04 + chaos * 0.06;
    let liquid = smoothstep(edge, -edge, d);
    let interior = smoothstep(0.15, -0.05, d);

    // dark ferrofluid palette with auroral breakup
    let n = fbm(p * 4.0 + warp * 3.0, 5);
    let darkBase = vec3<f32>(0.03, 0.035, 0.045);
    let oil = vec3<f32>(0.06, 0.07, 0.09) * (0.5 + n * 0.8);
    let aurora = vec3<f32>(0.25, 0.55, 0.85) * (mids * 0.6 + treble * 1.2);
    let ember = vec3<f32>(0.85, 0.35, 0.15) * (bass * 0.5 + chaos * 0.3);
    var col = darkBase + oil * liquid + aurora * interior * (1.0 - glyphStrength) + ember * bass * liquid;

    // specular gleam on glyph ridges
    let ridge = smoothstep(0.08, 0.0, abs(d - 0.04));
    col += vec3<f32>(0.7, 0.75, 0.8) * ridge * (0.4 + bassEnv * 0.8);

    // treble scatter
    let scatter = hash21(uv * 400.0 + time) * treble * 0.25;
    col += vec3<f32>(0.6, 0.7, 1.0) * scatter;

    // temporal feedback trail
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv01, 0.0);
    let decay = 0.90 - p4 * 0.12;
    col = mix(prev.rgb * decay, col, 0.25 + p4 * 0.25 + bass * 0.15);
    textureStore(dataTextureA, pixel, vec4<f32>(col, bassEnv));

    // color finishing: hue clamp, ACES, IGN dither
    col = hue_preserve_clamp(col, 1.25);
    col = aces(col * (0.85 + bassEnv * 0.35));
    col += (ign(vec2<f32>(pixel)) - 0.5) / 255.0;

    // transmission alpha: foreground metal opaque, background fades
    let metalOpacity = 0.88 + bassEnv * 0.10;
    let transmission = mix(0.35, 0.72, depth);
    var alpha = mix(transmission, metalOpacity, liquid * (0.5 + interior * 0.5));
    alpha = clamp(alpha + chaos * 0.08, 0.0, 1.0);

    textureStore(writeTexture, pixel, vec4<f32>(col * alpha, alpha));
    textureStore(writeDepthTexture, pixel, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
