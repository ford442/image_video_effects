// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Tree Fractal
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba, temporal-branch-sway, chromatic-leaves,
//            bass-growth-speed, upgraded-rgba, aces-tone-map
//  Complexity: High
//  Created: 2026-05-23
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

fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

fn hyperbolicTree(p: vec2<f32>, time: f32, bass: f32, mids: f32, depth: i32, branchAngle: f32) -> f32 {
    var d = 1000.0;
    let r = length(p);
    if (r > 0.98) { return d; }
    
    let mobius = p / (1.0 + sqrt(max(1.0 - r * r, 0.0001)));
    
    var pos = vec2<f32>(0.0, 0.0);
    var dir = vec2<f32>(0.0, 1.0);
    let len0 = 0.25;
    
    for (var i: i32 = 0; i < depth; i = i + 1) {
        let fi = f32(i);
        // Temporal sway memory: each branch remembers previous sway
        let prevSway = sin(time * 0.3 + fi * 0.5) * 0.1;
        let len = len0 * pow(0.65, fi) * (1.0 + bass * 0.2 * sin(time + fi));
        let sway = sin(time * 0.5 + fi * 0.7) * 0.15 * (1.0 + mids * 0.3) + prevSway;
        let leftDir = vec2<f32>(dir.x * cos(branchAngle + sway) - dir.y * sin(branchAngle + sway),
                                 dir.x * sin(branchAngle + sway) + dir.y * cos(branchAngle + sway));
        let rightDir = vec2<f32>(dir.x * cos(-branchAngle + sway) - dir.y * sin(-branchAngle + sway),
                                  dir.x * sin(-branchAngle + sway) + dir.y * cos(-branchAngle + sway));
        
        let nextPos = pos + dir * len;
        d = min(d, sdSegment(mobius, pos, nextPos) - len * 0.08);
        
        let side = hash12(mobius * 100.0 + vec2<f32>(fi, 0.0));
        pos = nextPos;
        dir = select(rightDir, leftDir, side > 0.5);
    }
    return d;
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
    
    let param1 = u.zoom_params.x;
    let param2 = u.zoom_params.y;
    let param3 = u.zoom_params.z;
    let param4 = u.zoom_params.w;
    
    let p = (uv - 0.5) * 2.0;
    let r = length(p);
    
    // Bass drives growth speed (depth changes more dynamically)
    let treeDepth = i32(mix(5.0, 12.0, param1 + bass * 0.3 * sin(time * 0.5)));
    let branchAngle = mix(0.3, 0.8, param2);
    let d = hyperbolicTree(p, time, bass, mids, treeDepth, branchAngle);
    
    let diskEdge = smoothstep(0.95, 1.0, r);
    
    let branchGlow = smoothstep(0.05, 0.0, d);
    let leafGlow = smoothstep(0.15, 0.0, d) * (1.0 - smoothstep(0.0, 0.05, d));
    
    // Chromatic leaf separation: R leaves on left, B on right
    let leafHue = fract(0.25 + r * 0.3 + time * 0.02 + mids * 0.1 + param3 * 0.2);
    let leftLeaf = mix(leafHue, 0.0, smoothstep(-0.1, 0.5, p.x));
    let rightLeaf = mix(leafHue, 0.55, smoothstep(-0.5, 0.1, p.x));
    let blendedHue = mix(leftLeaf, rightLeaf, smoothstep(-0.1, 0.1, p.x));
    
    let sat = mix(0.3, 0.9, param4 + treble * 0.3);
    let val = mix(0.1, 1.0, branchGlow + leafGlow * 0.5 + bass * 0.15);
    
    let rgb = hue2rgb(blendedHue) * sat + vec3<f32>(1.0 - sat) * val;
    let leafColor = vec3<f32>(0.2, 0.8, 0.3) * leafGlow * (1.0 + treble);
    
    // Temporal branch glow persistence
    let prev = textureSampleLevel(dataTextureC, u_sampler, uv, 0.0).rgb;
    let finalRGB = mix(rgb * val + leafColor, prev * 0.92, 0.05 + bass * 0.02);
    
    let alpha = clamp(val * 0.6 + branchGlow * 0.3 + leafGlow * 0.2 + 0.1 + bass * 0.05, 0.0, 1.0) * (1.0 - diskEdge);
    let finalColor = vec4<f32>(acesToneMap(finalRGB * 1.1), alpha);
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, vec2<i32>(global_id.xy), finalColor);
    textureStore(writeDepthTexture, vec2<i32>(global_id.xy), vec4<f32>(val * 0.5, 0.0, 0.0, 0.0));
}
