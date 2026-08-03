// ═══════════════════════════════════════════════════════════════════
//  Aperiodic Monotile Hat Tiling
//  Category: generative
//  Features: aperiodic-tiling, monotile, generative-pattern, audio-reactive, mouse-scale,
//            edge-glow, temporal-rotation, chromatic-edge-bloom, bass-scale-pulse, upgraded-rgba, aces-tone-map
//  Complexity: High
//  Chunks From: aperiodic tiling + improved visual layering
//  Created: 2026-05-23
//  Updated: 2026-05-31
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

const PI: f32 = 3.14159265359;

fn rotY(a: f32) -> mat3x3<f32> {
    let s = sin(a); let c = cos(a);
    return mat3x3<f32>(c, 0.0, s, 0.0, 1.0, 0.0, -s, 0.0, c);
}

// Compact analytic SDF library for the monotile-inspired relief sculpture.
fn sdSphere(p: vec3<f32>, r: f32) -> f32 { return length(p) - r; }
fn sdBox(p: vec3<f32>, b: vec3<f32>) -> f32 {
    let q = abs(p) - b;
    return length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0);
}
fn sdTorus(p: vec3<f32>, t: vec2<f32>) -> f32 {
    return length(vec2<f32>(length(p.xz) - t.x, p.y)) - t.y;
}
fn sdOctahedron(p: vec3<f32>, s: f32) -> f32 {
    let q = abs(p);
    return (q.x + q.y + q.z - s) * 0.57735027;
}
fn sdCapsule(p: vec3<f32>, a: vec3<f32>, b: vec3<f32>, r: f32) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-5), 0.0, 1.0);
    return length(pa - ba * h) - r;
}
fn smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// This is deliberately a stylized geometric echo of the 2D pattern, not a
// claim that the raymarched object itself is an exact mathematical monotile.
fn reliefDE(pIn: vec3<f32>, bass: f32, treble: f32, tileScale: f32, edgeWidth: f32) -> vec2<f32> {
    var p = rotY(u.config.x * (0.05 + u.zoom_params.y * 0.18) + u.zoom_config.y * 0.5) * pIn;
    p.y += sin(p.x * (4.0 + tileScale * 5.0) + u.config.x) * 0.025 * treble;
    let shell = max(sdSphere(p, 0.68 + bass * 0.06), -sdBox(p, vec3<f32>(0.43, 0.30, 0.43)));
    let crown = sdOctahedron(p - vec3<f32>(0.0, 0.18, 0.0), 0.58);
    let body = smin(shell, crown, 0.08 + edgeWidth * 0.05);
    let orbit = sdTorus(p, vec2<f32>(0.78 + tileScale * 0.08, 0.025 + edgeWidth * 0.035));
    var spokes = sdCapsule(p, vec3<f32>(-0.72, 0.0, 0.0), vec3<f32>(0.72, 0.0, 0.0), 0.022);
    spokes = min(spokes, sdCapsule(p, vec3<f32>(-0.36, -0.62, 0.0), vec3<f32>(0.36, 0.62, 0.0), 0.022));
    spokes = min(spokes, sdCapsule(p, vec3<f32>(-0.36, 0.62, 0.0), vec3<f32>(0.36, -0.62, 0.0), 0.022));
    var result = vec2<f32>(body, 1.0);
    if (orbit < result.x) { result = vec2<f32>(orbit, 2.0); }
    if (spokes < result.x) { result = vec2<f32>(spokes, 3.0); }
    return result;
}

fn reliefNormal(p: vec3<f32>, bass: f32, treble: f32, tileScale: f32, edgeWidth: f32) -> vec3<f32> {
    let e = vec2<f32>(0.003, 0.0);
    return normalize(vec3<f32>(
        reliefDE(p + e.xyy, bass, treble, tileScale, edgeWidth).x - reliefDE(p - e.xyy, bass, treble, tileScale, edgeWidth).x,
        reliefDE(p + e.yxy, bass, treble, tileScale, edgeWidth).x - reliefDE(p - e.yxy, bass, treble, tileScale, edgeWidth).x,
        reliefDE(p + e.yyx, bass, treble, tileScale, edgeWidth).x - reliefDE(p - e.yyx, bass, treble, tileScale, edgeWidth).x));
}

fn rot2(p: vec2<f32>, a: f32) -> vec2<f32> {
    let c = cos(a);
    let s = sin(a);
    return vec2<f32>(p.x * c - p.y * s, p.x * s + p.y * c);
}

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 = p3 + dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hue2rgb(h: f32) -> vec3<f32> {
    let k = vec3<f32>(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(h + k) * 6.0 - 3.0);
    return clamp(p - 1.0, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn hatTileDistance(uv: vec2<f32>, scale: f32) -> f32 {
    let p = uv * scale;
    let hex_q = p.x * 0.57735 + p.y * 0.33333;
    let hex_r = p.y * 0.66667;
    let hex_s = -hex_q - hex_r;
    let qf = floor(hex_q);
    let rf = floor(hex_r);
    let sf = floor(hex_s);
    let dq = abs(hex_q - qf - 0.5);
    let dr = abs(hex_r - rf - 0.5);
    let ds = abs(hex_s - sf - 0.5);
    let d = max(dq, max(dr, ds));
    return d * 2.0 - 0.5;
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
    if (global_id.x >= u32(u.config.z) || global_id.y >= u32(u.config.w)) { return; }
    
    let bass = plasmaBuffer[0].x;
    let mids = plasmaBuffer[0].y;
    let treble = plasmaBuffer[0].z;
    let time = u.config.x;
    let resolution = vec2<f32>(u.config.zw);
    let uv = (vec2<f32>(global_id.xy) + 0.5) / resolution;
    let mouse = u.zoom_config.yz;
    
    let param1 = u.zoom_params.x;
    let param2 = u.zoom_params.y;
    let param3 = u.zoom_params.z;
    let param4 = u.zoom_params.w;
    
    // Bass-driven scale pulse
    let scale = mix(8.0, 32.0, param1) * (1.0 + bass * 0.2);
    let rotSpeed = (param2 - 0.5) * 0.5;
    
    // Temporal rotation + mouse influence
    let rot = time * rotSpeed + mouse.x * 0.5;
    let p = rot2(uv - 0.5, rot) + 0.5;
    
    let d = hatTileDistance(p, scale);
    
    let tileID = floor(p.x * scale * 0.57735) + floor(p.y * scale * 0.66667) * 137.0;
    let tileHash = hash12(vec2<f32>(tileID, fract(tileID * 0.618)));
    
    let edgeWidth = mix(0.02, 0.08, param3);
    let edge = 1.0 - smoothstep(0.0, edgeWidth, abs(d));
    
    // Chromatic edge bloom: R on outer edge, B on inner
    let edgeR = 1.0 - smoothstep(0.0, edgeWidth * 1.2, abs(d - 0.01 * bass));
    let edgeB = 1.0 - smoothstep(0.0, edgeWidth * 1.2, abs(d + 0.01 * treble));
    let chromaEdge = vec3<f32>(edgeR, edge, edgeB) * (1.0 + treble);
    
    let hue = fract(tileHash + time * 0.03 + mids * 0.15 + uv.x * 0.1);
    let sat = mix(0.4, 0.9, param4 + treble * 0.3);
    let val = mix(0.15, 0.85, smoothstep(-0.3, 0.3, d) + bass * 0.2);
    
    let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat) * val;
    let edgeColor = vec3<f32>(1.0, 0.95, 0.8) * chromaEdge;

    var liveRGB = rgb * val + edgeColor;
    var reliefDepth = 0.0;

    // A budgeted raymarched relief gives the pattern a real geometric anchor.
    let screen = (uv - 0.5) * vec2<f32>(resolution.x / resolution.y, 1.0);
    let camera = rotY(time * 0.07 + mouse.x * 0.35);
    let ro = camera * vec3<f32>(0.0, 0.0, 2.65);
    let rd = camera * normalize(vec3<f32>(screen, -1.55));
    var rayT = 0.0;
    var hit = false;
    var material = 0.0;
    for (var i = 0; i < 42; i = i + 1) {
        let sample = reliefDE(ro + rd * rayT, bass, treble, param1, param3);
        if (sample.x < 0.003) { hit = true; material = sample.y; break; }
        rayT += max(sample.x * 0.82, 0.004);
        if (rayT > 5.5) { break; }
    }
    if (hit) {
        let pos = ro + rd * rayT;
        let n = reliefNormal(pos, bass, treble, param1, param3);
        let key = max(dot(n, normalize(vec3<f32>(0.75, 0.9, -0.45))), 0.0);
        let fill = max(dot(n, normalize(vec3<f32>(-0.65, 0.25, -0.6))), 0.0);
        let rim = pow(1.0 - max(dot(n, -rd), 0.0), 3.0);
        let reliefHue = fract(tileHash + material * 0.21 + time * 0.025);
        let reliefColor = hue2rgb(reliefHue) * mix(0.45, 1.0, param4);
        liveRGB += reliefColor * (0.18 + key * 0.72 + fill * 0.22 + rim * (0.7 + treble));
        reliefDepth = clamp(1.0 - rayT / 5.5, 0.0, 1.0);
    }
    
    // Temporal tile color persistence
    let prev = textureLoad(dataTextureC, vec2<i32>(global_id.xy), 0).rgb;
    let finalRGB = mix(liveRGB, prev * 0.94, 0.06 + bass * 0.02);
    
    let alpha = clamp(val * 0.6 + edge * 0.4 + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(acesToneMap(finalRGB * 1.1), alpha);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    let patternDepth = clamp(val * 0.5 + edge * 0.3, 0.0, 1.0);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(max(patternDepth, reliefDepth), 0.0, 0.0, 0.0));
}
