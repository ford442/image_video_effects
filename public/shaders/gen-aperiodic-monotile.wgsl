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
    let edge = smoothstep(edgeWidth, 0.0, abs(d));
    
    // Chromatic edge bloom: R on outer edge, B on inner
    let edgeR = smoothstep(edgeWidth * 1.2, 0.0, abs(d - 0.01 * bass));
    let edgeB = smoothstep(edgeWidth * 1.2, 0.0, abs(d + 0.01 * treble));
    let chromaEdge = vec3<f32>(edgeR, edge, edgeB) * (1.0 + treble);
    
    let hue = fract(tileHash + time * 0.03 + mids * 0.15 + uv.x * 0.1);
    let sat = mix(0.4, 0.9, param4 + treble * 0.3);
    let val = mix(0.15, 0.85, smoothstep(-0.3, 0.3, d) + bass * 0.2);
    
    let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat) * val;
    let edgeColor = vec3<f32>(1.0, 0.95, 0.8) * chromaEdge;
    
    // Temporal tile color persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let finalRGB = mix(rgb * val + edgeColor, prev * 0.94, 0.06 + bass * 0.02);
    
    let alpha = clamp(val * 0.6 + edge * 0.4 + bass * 0.05, 0.0, 1.0);
    let finalColor = vec4<f32>(acesToneMap(finalRGB * 1.1), alpha);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(val * 0.5 + edge * 0.3, 0.0, 0.0, 0.0));
}
