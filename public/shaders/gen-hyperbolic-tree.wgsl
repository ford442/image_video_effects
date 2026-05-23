// ═══════════════════════════════════════════════════════════════════
//  Hyperbolic Tree Fractal
//  Category: generative
//  Features: generative, audio-reactive, upgraded-rgba
//  Complexity: High
//  Created: 2026-05-23
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

// Distance to line segment
fn sdSegment(p: vec2<f32>, a: vec2<f32>, b: vec2<f32>) -> f32 {
    let pa = p - a;
    let ba = b - a;
    let h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    return length(pa - ba * h);
}

// Recursive tree branch in hyperbolic Poincare disk
fn hyperbolicTree(p: vec2<f32>, time: f32, bass: f32, mids: f32, depth: i32, branchAngle: f32) -> f32 {
    var d = 1000.0;
    let r = length(p);
    if (r > 0.98) { return d; }
    
    // Möbius transform for hyperbolic motion
    let mobius = p / (1.0 + sqrt(max(1.0 - r * r, 0.0001)));
    
    var pos = vec2<f32>(0.0, 0.0);
    var dir = vec2<f32>(0.0, 1.0);
    let len0 = 0.25;
    
    for (var i: i32 = 0; i < depth; i = i + 1) {
        let fi = f32(i);
        let len = len0 * pow(0.65, fi) * (1.0 + bass * 0.2 * sin(time + fi));
        let sway = sin(time * 0.5 + fi * 0.7) * 0.15 * (1.0 + mids * 0.3);
        let leftDir = vec2<f32>(dir.x * cos(branchAngle + sway) - dir.y * sin(branchAngle + sway),
                                 dir.x * sin(branchAngle + sway) + dir.y * cos(branchAngle + sway));
        let rightDir = vec2<f32>(dir.x * cos(-branchAngle + sway) - dir.y * sin(-branchAngle + sway),
                                  dir.x * sin(-branchAngle + sway) + dir.y * cos(-branchAngle + sway));
        
        let nextPos = pos + dir * len;
        d = min(d, sdSegment(mobius, pos, nextPos) - len * 0.08);
        
        // Branch selection based on pixel side
        let side = hash12(mobius * 100.0 + vec2<f32>(fi, 0.0));
        pos = nextPos;
        dir = select(rightDir, leftDir, side > 0.5);
    }
    return d;
}

@compute @workgroup_size(8, 8, 1)
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
    
    let treeDepth = i32(mix(5.0, 12.0, param1 + bass * 0.2));
    let branchAngle = mix(0.3, 0.8, param2);
    let d = hyperbolicTree(p, time, bass, mids, treeDepth, branchAngle);
    
    // Disk boundary
    let diskEdge = smoothstep(0.95, 1.0, r);
    
    // Glow from branches
    let branchGlow = smoothstep(0.05, 0.0, d);
    let leafGlow = smoothstep(0.15, 0.0, d) * (1.0 - smoothstep(0.0, 0.05, d));
    
    let hue = fract(0.25 + r * 0.3 + time * 0.02 + mids * 0.1 + param3 * 0.2);
    let sat = mix(0.3, 0.9, param4 + treble * 0.3);
    let val = mix(0.1, 1.0, branchGlow + leafGlow * 0.5 + bass * 0.15);
    
    let rgb = hue2rgb(hue) * sat + vec3<f32>(1.0 - sat) * val;
    let leafColor = vec3<f32>(0.2, 0.8, 0.3) * leafGlow * (1.0 + treble);
    
    let finalRGB = rgb * val + leafColor;
    let alpha = clamp(val * 0.6 + branchGlow * 0.3 + leafGlow * 0.2 + 0.1, 0.0, 1.0) * (1.0 - diskEdge);
    let finalColor = vec4<f32>(finalRGB, alpha);
    
    let depth = textureLoad(readDepthTexture, vec2<i32>(global_id.xy), 0).r;
    
    textureStore(writeTexture, vec2<i32>(global_id.xy), finalColor);
    textureStore(dataTextureA, global_id.xy, finalColor);
    textureStore(writeDepthTexture, global_id.xy, vec4<f32>(depth, 0.0, 0.0, 0.0));
}
